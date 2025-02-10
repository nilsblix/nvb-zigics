const std = @import("std");
const Allocator = std.mem.Allocator;
const nmath = @import("nmath.zig");
const Vector2 = nmath.Vector2;
const rb_mod = @import("rigidbody.zig");
const RigidBody = rb_mod.RigidBody;
const fg_mod = @import("force-generator.zig");
const ForceGenerator = fg_mod.ForceGenerator;

// FIXME: transform camera / and always update properties like mult and size and viewport and fuck all else
pub const Units = struct {
    pub const Size = struct {
        width: f32,
        height: f32,
    };

    const TransformMult = struct {
        w2s: f32,
        s2w: f32,
    };

    const Camera = struct {
        pos: nmath.Vector2,
        zoom: f32,
        viewport: Size,
    };

    camera: Camera,
    mult: TransformMult,
    screen_size: Size,

    const Self = @This();
    /// Assumes that screen_size and world_size have the same proportions.
    /// Assumes that in screen units top left is (0,0).
    pub fn init(screen_size: Size, default_world_width: f32) Self {
        const aspect_ratio = screen_size.width / screen_size.height;

        const default_world_size = Size{ .width = default_world_width, .height = default_world_width * aspect_ratio };

        const x = default_world_size.width / 2;
        const y = default_world_size.height / 2;
        const camera = Camera{
            .pos = Vector2.init(x, y),
            .zoom = 1.0,
            .viewport = default_world_size,
        };

        const mult = TransformMult{
            .w2s = screen_size.width / default_world_width,
            .s2w = default_world_width / screen_size.width,
        };

        return .{
            .camera = camera,
            .mult = mult,
            .screen_size = screen_size,
        };
    }

    /// Will flip y as world bottom-left is (0,0)
    pub fn w2s(self: Self, pos: Vector2) Vector2 {
        const x = pos.x * self.mult.s2w / self.camera.zoom - self.camera.pos.x;
        const y = self.screen_size.height - (pos.y * self.mult.s2w) / self.camera.zoom - self.camera.pos.y;
        return Vector2.init(x, y);
    }

    /// Will flip y as world bottom-left is (0,0)
    pub fn s2w(self: Self, pos: Vector2) Vector2 {
        const x = (pos.x + self.x) * self.camera.zoom * self.mult.s2w;
        const y = (pos.y + self.camera.pos.y - self.screen_size.height) * self.camera.zoom * self.mult.w2s;
        return Vector2.init(x, y);
    }

    /// Max x from [oldmin -> oldmax] ==> [newmin -> newmax]
    pub fn map(x: f32, omin: f32, omax: f32, nmin: f32, nmax: f32) f32 {
        return nmin + ((x - omin) * (nmin - nmax)) / (omin - omax);
    }
};

pub const Physics = struct {
    bodies: std.ArrayList(RigidBody),
    force_generators: std.ArrayList(ForceGenerator),
    // joints: std.ArrayList(Joint),

    const Self = @This();
    /// Assumes that screen_size and world_size have the same proportions.
    /// Assumes that in screen units top left is (0,0).
    pub fn init(alloc: Allocator) Self {
        return .{
            .bodies = std.ArrayList(RigidBody).init(alloc),
            .force_generators = std.ArrayList(ForceGenerator).init(alloc),
            // .joints = std.ArrayList(Joint).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.force_generators.deinit();
        // self.joints.deinit();
        self.bodies.deinit();
    }

    pub fn process(self: *Self, dt: f32) void {
        for (self.force_generators.items) |*gen| {
            gen.apply(self.bodies);
        }

        for (self.bodies.items) |*body| {
            std.debug.print("before \n", .{});
            body.print();

            var props: *RigidBody.Props = &body.props;

            props.momentum = nmath.addmult2(props.momentum, props.force, dt);
            props.pos = nmath.addmult2(props.pos, props.momentum, dt);

            props.ang_momentum += props.torque * dt;
            props.angle += props.ang_momentum * dt;

            props.force = Vector2.zero;
            props.torque = 0;

            std.debug.print("after \n", .{});
            body.print();
        }
    }
};
//
// pub const World = struct {
//     physics: Physics,
//     units: ?Units,
//
//     const Self = @This();
//     pub fn init(alloc: Allocator, screen_size: Units.Size, default_world_width: f32) World {
//         return .{
//             .physics = Physics.init(alloc, screen_size, default_world_width),
//             .units = null,
//         };
//     }
//
//     pub fn deinit(self: *Self) void {
//         self.physics.deinit();
//     }
//
//     pub fn process(self: *Self, dt: f32) void {
//         self.physics.process(dt);
//     }
// };
