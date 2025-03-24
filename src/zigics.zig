const std = @import("std");
const Allocator = std.mem.Allocator;
const nmath = @import("nmath.zig");
const Vector2 = nmath.Vector2;
const rb_mod = @import("rigidbody.zig");
const RigidBody = rb_mod.RigidBody;
const fg_mod = @import("force_generator.zig");
const ForceGenerator = fg_mod.ForceGenerator;
const rl = @import("raylib");
const def_rend = @import("default_renderer.zig");
pub const Units = def_rend.Units;
const Renderer = def_rend.Renderer;
const clsn = @import("collision.zig");
const qtree = @import("quadtree.zig");
const QuadTree = qtree.QuadTree;
const ctr_mod = @import("constraint.zig");
const Constraint = ctr_mod.Constraint;

pub const EntityFactory = struct {
    pub const BodyOptions = struct {
        pos: Vector2,
        vel: Vector2 = .{},
        angle: f32 = 0.0,
        omega: f32 = 0.0,
        mu_s: f32 = 0.5,
        mu_d: f32 = 0.4,
        mass_prop: union(enum) {
            /// kg / m^2
            density: f32,
            mass: f32,
        },
    };

    pub const DiscOptions = struct {
        radius: f32 = 1.0,
    };

    pub const RectangleOptions = struct {
        width: f32 = 1.0,
        height: f32 = 0.5,
    };

    pub const GeometryOptions = union(enum) {
        disc: DiscOptions,
        rectangle: RectangleOptions,
    };

    solver: *Solver,

    const Self = @This();

    pub fn makeDiscBody(self: *Self, rigid_opt: BodyOptions, geometry_opt: DiscOptions) !*RigidBody {
        const mass = switch (rigid_opt.mass_prop) {
            .mass => |m| m,
            .density => |density| @as(f32, std.math.pi) * geometry_opt.radius * geometry_opt.radius * density,
        };

        var body = try rb_mod.DiscBody.init(self.solver.alloc, rigid_opt.pos, rigid_opt.angle, mass, rigid_opt.mu_s, rigid_opt.mu_d, geometry_opt.radius);

        body.props.momentum = nmath.scale2(rigid_opt.vel, mass);
        body.props.ang_momentum = rigid_opt.omega * body.props.inertia;

        try self.solver.bodies.append(body);
        return &self.solver.bodies.items[self.solver.bodies.items.len - 1];
    }

    pub fn makeRectangleBody(self: *Self, rigid_opt: BodyOptions, geometry_opt: RectangleOptions) !*RigidBody {
        const mass = switch (rigid_opt.mass_prop) {
            .mass => |m| m,
            .density => |density| geometry_opt.width * geometry_opt.height * density,
        };

        var body = try rb_mod.RectangleBody.init(self.solver.alloc, rigid_opt.pos, rigid_opt.angle, mass, rigid_opt.mu_s, rigid_opt.mu_d, geometry_opt.width, geometry_opt.height);

        body.props.momentum = nmath.scale2(rigid_opt.vel, mass);
        body.props.ang_momentum = rigid_opt.omega * body.props.inertia;

        try self.solver.bodies.append(body);
        return &self.solver.bodies.items[self.solver.bodies.items.len - 1];
    }

    pub fn makeDownwardsGravity(self: *Self, g: f32) !void {
        try self.solver.force_generators.append(try fg_mod.DownwardsGravity.init(self.solver.alloc, g));
    }

    pub fn makeSingleLinkJoint(self: *Self, params: Constraint.Parameters, body: *RigidBody, r: Vector2, q: Vector2, dist: f32) !*Constraint {
        const ctr = try ctr_mod.SingleLinkJoint.init(self.solver.alloc, params, body, r, q, dist);
        try self.solver.constraints.append(ctr);
        return &self.solver.constraints.items[self.solver.constraints.items.len - 1];
    }

    pub fn makeMotorJoint(self: *Self, params: Constraint.Parameters, body: *RigidBody, target_omega: f32) !*Constraint {
        const ctr = try ctr_mod.MotorJoint.init(self.solver.alloc, params, body, target_omega);
        try self.solver.constraints.append(ctr);
        return &self.solver.constraints.items[self.solver.constraints.items.len - 1];
    }
};

pub const Solver = struct {
    alloc: Allocator,
    bodies: std.ArrayList(RigidBody),
    force_generators: std.ArrayList(ForceGenerator),
    manifolds: std.AutoArrayHashMap(clsn.CollisionKey, clsn.CollisionManifold),
    quadtree: QuadTree,
    constraints: std.ArrayList(Constraint),

    const Self = @This();
    pub fn init(alloc: Allocator, comptime quadtree_node_threshold: usize, comptime quadtree_max_depth: usize, comptime quadtree_min_node_side_len: f32) !Self {
        return .{
            .alloc = alloc,
            .bodies = std.ArrayList(RigidBody).init(alloc),
            .force_generators = std.ArrayList(ForceGenerator).init(alloc),
            .manifolds = std.AutoArrayHashMap(clsn.CollisionKey, clsn.CollisionManifold).init(alloc),
            .quadtree = try QuadTree.init(alloc, quadtree_node_threshold, quadtree_max_depth, quadtree_min_node_side_len),
            .constraints = std.ArrayList(Constraint).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.manifolds.deinit();
        self.quadtree.deinit(self.alloc);
        for (self.constraints.items) |*constraint| {
            constraint.deinit(self.alloc);
        }
        self.constraints.deinit();
        for (self.force_generators.items) |*gen| {
            gen.deinit(self.alloc);
        }
        self.force_generators.deinit();
        for (self.bodies.items) |*body| {
            body.deinit(self.alloc);
        }
        self.bodies.deinit();
    }

    pub fn clear(self: *Self, alloc: Allocator) !void {
        self.deinit();
        self.bodies = std.ArrayList(RigidBody).init(alloc);
        self.force_generators = std.ArrayList(ForceGenerator).init(alloc);
        self.manifolds = std.AutoArrayHashMap(clsn.CollisionKey, clsn.CollisionManifold).init(alloc);
        self.quadtree.initRoot(alloc);
        self.constraints = std.ArrayList(Constraint).init(alloc);
    }

    pub fn process(self: *Self, alloc: Allocator, dt: f32, sub_steps: usize, collision_iters: usize) !void {
        const f32_sub: f32 = @floatFromInt(sub_steps);
        const sub_dt = dt / f32_sub;
        const inv_sub_dt = 1 / sub_dt;

        try self.updateManifolds(alloc);

        for (0..sub_steps) |_| {
            for (self.force_generators.items) |*gen| {
                gen.apply(self.bodies);
            }

            for (self.bodies.items) |*body| {
                body.updateAABB();
                if (body.static) continue;
                var props: *RigidBody.Props = &body.props;

                props.momentum.addmult(props.force, sub_dt);
                props.ang_momentum += props.torque * sub_dt;
            }

            var iter = self.manifolds.iterator();
            while (iter.next()) |entry| {
                const manifold = entry.value_ptr;
                const key = entry.key_ptr.*;
                manifold.updateTGSDepth(key);
                manifold.preStep(key);
            }

            for (0..collision_iters) |_| {
                for (self.constraints.items) |*constraint| {
                    constraint.solve(sub_dt, inv_sub_dt);
                }
                iter.reset();
                while (iter.next()) |entry| {
                    const manifold = entry.value_ptr;
                    const key = entry.key_ptr.*;
                    manifold.applyImpulses(key, sub_dt);
                }
            }

            for (self.bodies.items) |*body| {
                if (body.static) continue;
                var props: *RigidBody.Props = &body.props;

                props.pos.addmult(props.momentum, sub_dt / props.mass);
                props.angle += props.ang_momentum * sub_dt / props.inertia;

                props.force = .{};
                props.torque = 0;
            }
        }
    }

    fn updateManifolds(self: *Self, alloc: Allocator) !void {
        self.quadtree.clear(alloc);

        try self.quadtree.insertValues(alloc, self.bodies.items);

        var queries = std.ArrayList(*RigidBody).init(alloc);
        defer queries.deinit();

        // self.manifolds.clearAndFree();
        self.manifolds.clearRetainingCapacity();

        for (self.bodies.items) |*body1| {
            queries.clearRetainingCapacity();
            // queries.clearAndFree();
            try self.quadtree.queryAABB(body1.aabb, &queries);

            for (queries.items) |body2| {
                if (body1.static and body2.static) continue;
                if (body1.ptr == body2.ptr) continue;

                var tmp = clsn.CollisionKey{ .ref_body = body1, .inc_body = body2 };
                if (!self.manifolds.contains(tmp)) {
                    tmp = clsn.CollisionKey{ .ref_body = body2, .inc_body = body1 };
                    if (!self.manifolds.contains(tmp)) {
                        if (!body1.aabb.intersects(body2.aabb)) continue;

                        const sat = clsn.performNarrowSAT(body1, body2);

                        if (!sat.collides) continue;

                        const manifold = clsn.CollisionManifold{
                            .normal = sat.normal,
                            .points = sat.key.ref_body.identifyCollisionPoints(sat.key.inc_body, sat.reference_normal_id),
                            .prev_angle_1 = sat.key.ref_body.props.angle,
                            .prev_angle_2 = sat.key.inc_body.props.angle,
                        };

                        try self.manifolds.put(sat.key, manifold);
                    }
                }
            }
        }
    }

    pub fn entityFactory(self: *Self) EntityFactory {
        return EntityFactory{ .solver = self };
    }
};

pub const World = struct {
    solver: Solver,
    renderer: ?Renderer,

    const Self = @This();
    pub fn init(alloc: Allocator, screen_size: Units.Size, default_world_width: f32, init_renderer: bool, comptime quadtree_node_threshold: usize, comptime quadtree_max_depth: usize, comptime quadtree_min_node_side_len: f32) !Self {
        return .{
            .solver = try Solver.init(alloc, quadtree_node_threshold, quadtree_max_depth, quadtree_min_node_side_len),
            .renderer = if (init_renderer) Renderer.init(screen_size, default_world_width) else null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.solver.deinit();
    }

    pub fn render(self: *Self, show_collisions: bool, show_qtree: bool, show_aabbs: bool) void {
        if (self.renderer) |*rend| {
            rend.render(self.solver, show_collisions, show_qtree, show_aabbs);
        }
    }
};
