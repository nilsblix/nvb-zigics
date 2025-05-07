// CLEAN:
// Use these for making comments/noting code:
// - FIXME: An issue that needs to be fixed.
// - POTENTIAL: I have spotted something that I think works, but could be a cause for some weird bug.
// - CLEAN: Remove something/general cleanup of code.

const std = @import("std");
const rl = @import("raylib");
const zigics = @import("zigics.zig");
const rigidbody = @import("rigidbody.zig");
const forcegenerator = @import("force_generator.zig");
const nmath = @import("nmath.zig");
const Vector2 = nmath.Vector2;
const Allocator = std.mem.Allocator;
const collision = @import("collision.zig");
const demos = @import("demos.zig");
const ctr_mod = @import("constraint.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // const alloc = std.heap.page_allocator;
    // const alloc = std.heap.c_allocator;

    // const screen_width = 1536;
    // const screen_height = 864;
    const screen_width = 1280;
    const screen_height = 720;
    // const screen_width = 1920;
    // const screen_height = 1080;

    var world = try zigics.World.init(alloc, .{ .width = screen_width, .height = screen_height }, 10, true);
    defer world.deinit();

    try demos.setup1(&world.solver);

    var mouse_spring = MouseSpring{};

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "zigics");
    defer rl.closeWindow();

    const HZ: i32 = 60;
    const STANDARD_DT: f32 = 1 / @as(f32, HZ);
    const SUB_STEPS = 2;
    const COLLISION_ITERS = 6;
    rl.setTargetFPS(HZ);

    var simulating: bool = false;
    var show_collisions: bool = true;
    var show_aabbs: bool = false;
    var slow_motion = false;
    var high_speed = false;
    var steps: u32 = 0;

    var tried_steps: u32 = 0;

    var sim_dt: f32 = -1;
    var render_dt: f32 = -1;

    var screen_prev_mouse_pos: Vector2 = .{};
    var screen_mouse_pos: Vector2 = .{};
    var prev_mouse_pos: Vector2 = .{};
    var mouse_pos: Vector2 = .{};

    while (!rl.windowShouldClose()) {
        screen_prev_mouse_pos = screen_mouse_pos;
        prev_mouse_pos = mouse_pos;

        const rl_pos = rl.getMousePosition();
        screen_mouse_pos = Vector2.init(rl_pos.x, rl_pos.y);
        mouse_pos = world.renderer.?.units.s2w(Vector2.init(screen_mouse_pos.x, screen_mouse_pos.y));

        const delta_screen = nmath.sub2(screen_mouse_pos, screen_prev_mouse_pos);
        var world_delta_mouse_pos = nmath.scale2(delta_screen, world.renderer.?.units.mult.s2w);
        world_delta_mouse_pos.y *= -1;

        rl.beginDrawing();
        defer rl.endDrawing();

        if (world.renderer) |rend| {
            try mouse_spring.update(alloc, rend.units, &world.solver);
        }

        const delta_wheel = rl.getMouseWheelMove();
        if (delta_wheel != 0) {
            world.renderer.?.adjustCameraZoom(std.math.exp(delta_wheel / 100), screen_mouse_pos);
        }

        if (rl.isMouseButtonDown(.left)) {
            // const mouse_delta = nmath.sub2(mouse_pos, prev_mouse_pos);
            world.renderer.?.adjustCameraPos(world_delta_mouse_pos);
        }

        if (rl.isKeyPressed(.space)) {
            simulating = !simulating;
        }

        if (rl.isKeyPressed(.d)) {
            show_collisions = !show_collisions;
        }

        if (rl.isKeyPressed(.k)) {
            slow_motion = !slow_motion;
        }

        if (rl.isKeyPressed(.f)) {
            high_speed = !high_speed;
        }

        if (rl.isKeyPressed(.a)) {
            show_aabbs = !show_aabbs;
        }

        if (rl.isKeyPressed(.one)) {
            try world.solver.clear(alloc);
            steps = 0;
            try demos.setup1(&world.solver);
        }

        if (rl.isKeyPressed(.two)) {
            try world.solver.clear(alloc);
            steps = 0;
            try demos.setup2(&world.solver);
        }


        tried_steps += 1;
        if (simulating) {
            const start = std.time.nanoTimestamp();
            const mod = @mod(@as(f32, @floatFromInt(tried_steps)), 8) == 0;

            if (slow_motion and mod) {
                steps += 1;
                // try world.solver.process(alloc, STANDARD_DT / SUB_STEPS, 1, COLLISION_ITERS);
                try world.solver.process(alloc, STANDARD_DT, SUB_STEPS, COLLISION_ITERS);
            } else if (!slow_motion and high_speed) {
                for (0..3) |_| {
                    steps += 1;
                    try world.solver.process(alloc, STANDARD_DT, SUB_STEPS, COLLISION_ITERS);
                }
            } else if (!slow_motion and !high_speed) {
                steps += 1;
                try world.solver.process(alloc, STANDARD_DT, SUB_STEPS, COLLISION_ITERS);
            }

            const end = std.time.nanoTimestamp();
            sim_dt = @floatFromInt(end - start);
        } else {
            if (rl.isKeyPressed(.right)) {
                steps += 1;
                const start = std.time.nanoTimestamp();
                try world.solver.process(alloc, STANDARD_DT, SUB_STEPS, COLLISION_ITERS);
                const end = std.time.nanoTimestamp();
                sim_dt = @floatFromInt(end - start);
            }

            rl.drawText("paused", 5, 0, 64, rl.Color.white);
        }

        rl.clearBackground(.{ .r = 18, .g = 18, .b = 18, .a = 1 });
        const start = std.time.nanoTimestamp();
        try world.render(show_collisions, show_aabbs);
        const end = std.time.nanoTimestamp();
        render_dt = @floatFromInt(end - start);

        const font_size = 16;

        rl.drawText(rl.textFormat("mouse pos = %.3f, %.3f", .{ mouse_pos.x, mouse_pos.y }), 5, screen_height - 4 * font_size, font_size, rl.Color.white);

        rl.drawText(rl.textFormat("bodies = %d : manifolds = %d", .{ world.solver.bodies.count(), world.solver.manifolds.count() }), 5, screen_height - 3 * font_size, font_size, rl.Color.white);

        rl.drawText(rl.textFormat("sr = %.3f ms : render = %.3f ms", .{ sim_dt / 1e6, render_dt / 1e6 }), 5, screen_height - 2 * font_size, font_size, rl.Color.white);

        rl.drawText(rl.textFormat("%.3f ms : steps = %d", .{ STANDARD_DT * 1e3, steps }), 5, screen_height - font_size, font_size, rl.Color.white);
    }
}

const MouseSpring = struct {
    active: bool = false,

    const Self = @This();

    pub fn update(self: *Self, alloc: Allocator, units: zigics.Units, solver: *zigics.Solver) !void {
        const rl_pos = rl.getMousePosition();
        const mouse_pos = units.s2w(Vector2.init(rl_pos.x, rl_pos.y));

        if (!self.active and rl.isKeyPressed(.v)) {
            var iter = solver.bodies.iterator();
            while (iter.next()) |*entry| {
                var body = entry.value_ptr;
                if (body.static) continue;
                if (body.isInside(mouse_pos)) {
                    const r_rotated = nmath.sub2(mouse_pos, body.props.pos);
                    const r = nmath.rotate2(r_rotated, -body.props.angle);

                    var fac = solver.entityFactory();

                    const max: f32 = 40;
                    const params = ctr_mod.Constraint.Parameters{
                        .beta = 100,
                        .lower_lambda = -max,
                        .upper_lambda = max,
                    };
                    // _ = try fac.makeFixedAngleJoint(params, body.id, body.props.angle);
                    _ = try fac.makeSingleLinkJoint(params, body.id, r, mouse_pos, 0.0);
                    self.active = true;
                    return;
                }
            }
        }

        if (self.active and rl.isKeyDown(.v)) {
            const item = solver.constraints.items[solver.constraints.items.len - 1];
            const joint: *ctr_mod.SingleLinkJoint = @ptrCast(@alignCast(item.ptr));
            joint.q = mouse_pos;
        }

        if (self.active and rl.isKeyReleased(.v)) {
            var item = solver.constraints.pop();
            item.?.deinit(alloc);
            // item = solver.constraints.pop();
            // item.?.deinit(alloc);
            self.active = false;
        }
    }
};
