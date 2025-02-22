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

pub const Physics = struct {
    alloc: Allocator,
    bodies: std.ArrayList(RigidBody),
    force_generators: std.ArrayList(ForceGenerator),

    const Self = @This();
    pub fn init(alloc: Allocator) Self {
        return .{
            .alloc = alloc,
            .bodies = std.ArrayList(RigidBody).init(alloc),
            .force_generators = std.ArrayList(ForceGenerator).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.force_generators.items) |*gen| {
            gen.deinit(self.alloc);
        }
        self.force_generators.deinit();
        for (self.bodies.items) |*body| {
            body.deinit(self.alloc);
        }
        self.bodies.deinit();
    }

    pub fn process(self: *Self, dt: f32) void {
        for (self.force_generators.items) |*gen| {
            gen.apply(self.bodies);
        }

        for (self.bodies.items) |*body| {
            var props: *RigidBody.Props = &body.props;

            props.momentum.addmult(props.force, dt);
            props.pos.addmult(props.momentum, dt / props.mass);

            props.ang_momentum += props.torque * dt;
            props.angle += props.ang_momentum * dt / props.inertia;

            props.force = .{};
            props.torque = 0;
        }
    }

    pub fn getEnergy(self: Self) f32 {
        var E: f32 = 0;
        for (self.force_generators.items) |*gen| {
            E += gen.energy(self.bodies);
        }
        for (self.bodies.items) |*body| {
            const len2 = nmath.length2sq(nmath.scale2(body.props.momentum, 1 / body.props.mass));
            E += 1 / 2 * body.props.mass * len2;
            const ang_vel = body.props.ang_momentum / body.props.inertia;
            E += 1 / 2 * body.props.inertia * ang_vel * ang_vel;
        }
        return E;
    }

    pub fn makeDiscBody(self: *Self, pos: Vector2, mass: f32, radius: f32) !void {
        const body: rb_mod.RigidBody = try rb_mod.DiscBody.init(self.alloc, pos, 0, mass, radius);
        try self.bodies.append(body);
    }

    pub fn makeRectangleBody(self: *Self, pos: Vector2, mass: f32, width: f32, height: f32) !void {
        const body: rb_mod.RigidBody = try rb_mod.RectangleBody.init(self.alloc, pos, 0, mass, width, height);
        try self.bodies.append(body);
    }
};

pub const World = struct {
    physics: Physics,
    renderer: ?Renderer,

    const Self = @This();
    pub fn init(alloc: Allocator, screen_size: Units.Size, default_world_width: f32, init_renderer: bool) World {
        return .{
            .physics = Physics.init(alloc),
            .renderer = if (init_renderer) Renderer.init(screen_size, default_world_width) else null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.physics.deinit();
    }

    pub fn process(self: *Self, dt: f32) void {
        self.physics.process(dt);
    }

    pub fn render(self: *Self) void {
        if (self.renderer) |*rend| {
            const ext = 0.5;
            const left = rend.units.w2s(Vector2.init(-ext, 0));
            const top = rend.units.w2s(Vector2.init(0, ext));
            const bottom = rend.units.w2s(Vector2.init(0, -ext));
            const right = rend.units.w2s(Vector2.init(ext, 0));

            const rl_left = rl.Vector2.init(left.x, left.y);
            const rl_top = rl.Vector2.init(top.x, top.y);
            const rl_bottom = rl.Vector2.init(bottom.x, bottom.y);
            const rl_right = rl.Vector2.init(right.x, right.y);

            const width = rend.units.mult.w2s * 0.02;

            rl.drawLineEx(rl_left, rl_right, width, rl.Color.red);
            rl.drawLineEx(rl_bottom, rl_top, width, rl.Color.red);

            rend.render(self.physics);
        }
    }
};
