const std = @import("std");
const nmath = @import("nmath.zig");
const Vector2 = nmath.Vector2;
const Allocator = std.mem.Allocator;
const rb_mod = @import("rigidbody.zig");
const RigidBody = rb_mod.RigidBody;

pub const Constraints = enum {
    single_link_joint,
    motor_joint,
};

pub const Constraint = struct {
    const VTable = struct {
        deinit: *const fn (ctrself: *Constraint, alloc: Allocator) void,
        solve: *const fn (ctrself: *Constraint, bodies: std.AutoArrayHashMap(RigidBody.Id, RigidBody), dt: f32, inv_dt: f32) anyerror!void,
    };

    pub const Parameters = struct {
        beta: f32 = 10,
        upper_lambda: f32 = std.math.inf(f32),
        lower_lambda: f32 = -std.math.inf(f32),
    };

    params: Parameters,
    type: Constraints,
    vtable: VTable,
    ptr: *anyopaque,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.vtable.deinit(self, alloc);
    }

    pub fn solve(self: *Self, bodies: std.AutoArrayHashMap(RigidBody.Id, RigidBody), dt: f32, inv_dt: f32) !void {
        try self.vtable.solve(self, bodies, dt, inv_dt);
    }
};

pub const FixedAngleJoint = struct {
    id: RigidBody.Id,
    theta_t: f32,

    const VTable = Constraint.VTable{
        .deinit = MotorJoint.deinit,
        .solve = MotorJoint.solve,
    };

    const Self = @This();

    pub fn init(alloc: Allocator, params: Constraint.Parameters, id: RigidBody.Id, omega_t: f32) !Constraint {
        const joint = try alloc.create(MotorJoint);
        joint.id = id;
        joint.omega_t = omega_t;

        return Constraint{
            .type = Constraints.motor_joint,
            .params = params,
            .ptr = joint,
            .vtable = MotorJoint.VTable,
        };
    }

    pub fn deinit(ctrself: *Constraint, alloc: Allocator) void {
        const self: *Self = @ptrCast(@alignCast(ctrself.ptr));
        alloc.destroy(self);
    }

    pub fn solve(ctrself: *Constraint, bodies: std.AutoArrayHashMap(RigidBody.Id, RigidBody), dt: f32, inv_dt: f32) !void {
        const self: *Self = @ptrCast(@alignCast(ctrself.ptr));
        const entry = bodies.getEntry(self.id) orelse return error.InvalidRigidBodyId;
        var body = entry.value_ptr;

        _ = dt;
        _ = inv_dt;
        // const omega = body.props.ang_momentum / body.props.inertia;
        // const delta = self.omega_t - omega;

        // FIXME: This constraint math is COMPLETELY FUCKED. Redo ts immediately...
        body.props.angle = self.theta_t;
        body.props.torque = 0;
        body.props.ang_momentum = 0;
    }
};

pub const MotorJoint = struct {
    id: RigidBody.Id,
    omega_t: f32,

    const VTable = Constraint.VTable{
        .deinit = MotorJoint.deinit,
        .solve = MotorJoint.solve,
    };

    const Self = @This();

    pub fn init(alloc: Allocator, params: Constraint.Parameters, id: RigidBody.Id, omega_t: f32) !Constraint {
        const joint = try alloc.create(MotorJoint);
        joint.id = id;
        joint.omega_t = omega_t;

        return Constraint{
            .type = Constraints.motor_joint,
            .params = params,
            .ptr = joint,
            .vtable = MotorJoint.VTable,
        };
    }

    pub fn deinit(ctrself: *Constraint, alloc: Allocator) void {
        const self: *Self = @ptrCast(@alignCast(ctrself.ptr));
        alloc.destroy(self);
    }

    pub fn solve(ctrself: *Constraint, bodies: std.AutoArrayHashMap(RigidBody.Id, RigidBody), dt: f32, inv_dt: f32) !void {
        const self: *Self = @ptrCast(@alignCast(ctrself.ptr));
        const entry = bodies.getEntry(self.id) orelse return error.InvalidRigidBodyId;
        var body = entry.value_ptr;

        _ = dt;
        _ = inv_dt;
        const omega = body.props.ang_momentum / body.props.inertia;
        const delta = self.omega_t - omega;

        // FIXME: This constraint math is COMPLETELY FUCKED. Redo ts immediately...
        body.props.ang_momentum += ctrself.params.beta * delta;
    }
};

pub const SingleLinkJoint = struct {
    id: RigidBody.Id,
    local_r: Vector2,
    q: Vector2,
    distance: f32,

    const VTable = Constraint.VTable{
        .deinit = SingleLinkJoint.deinit,
        .solve = SingleLinkJoint.solve,
    };

    const Self = @This();

    pub fn init(alloc: Allocator, params: Constraint.Parameters, id: RigidBody.Id, local_r: Vector2, q: Vector2, distance: f32) !Constraint {
        const joint = try alloc.create(SingleLinkJoint);
        joint.id = id;
        joint.local_r = local_r;
        joint.q = q;
        joint.distance = distance;

        return Constraint{
            .type = Constraints.single_link_joint,
            .params = params,
            .ptr = joint,
            .vtable = SingleLinkJoint.VTable,
        };
    }

    pub fn deinit(ctrself: *Constraint, alloc: Allocator) void {
        const self: *Self = @ptrCast(@alignCast(ctrself.ptr));
        alloc.destroy(self);
    }

    pub fn solve(ctrself: *Constraint, bodies: std.AutoArrayHashMap(RigidBody.Id, RigidBody), dt: f32, inv_dt: f32) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctrself.ptr));
        const entry = bodies.getEntry(self.id) orelse return error.InvalidRigidBodyId;
        var body = entry.value_ptr;

        const r = nmath.rotate2(self.local_r, body.props.angle);
        const k = nmath.sub2(nmath.add2(body.props.pos, r), self.q);
        const c = 0.5 * (nmath.dot2(k, k) - self.distance * self.distance);

        const inv_m = 1 / body.props.mass;
        var inv_i: f32 = undefined;
        const k_len = nmath.length2(k);
        if (k_len < 1e-2) {
            inv_i = 1 / body.props.inertia;
        } else {
            const n = nmath.scale2(k, 1 / k_len);
            const rn = nmath.cross2(r, n);
            inv_i = rn * rn / body.props.inertia;
        }
        const w = inv_i + inv_m;

        const v = nmath.scale2(body.props.momentum, inv_m);
        const omega = body.props.ang_momentum / body.props.inertia;

        const r_prime = nmath.rotate90counterclockwise(r);
        const r_prime_k = nmath.dot2(r_prime, k);
        const jv = nmath.dot2(k, v) + r_prime_k * omega;
        const jjT = nmath.dot2(k, k) + r_prime_k * r_prime_k;

        var lambda = inv_dt * (-ctrself.params.beta * c - jv) / (w * jjT);

        lambda = std.math.clamp(lambda, ctrself.params.lower_lambda, ctrself.params.upper_lambda);

        const fext = nmath.scale2(k, lambda);
        const torque = lambda * r_prime_k;

        const p = nmath.scale2(fext, dt);
        const p_ang = torque * dt;

        body.props.momentum.add(p);
        body.props.ang_momentum += p_ang;
    }
};
