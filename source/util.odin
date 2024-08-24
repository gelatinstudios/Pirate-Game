
package pirates

import "core:math"
import "core:c"

import rl "vendor:raylib"

expand_to_v3 :: proc(v: v2) -> v3 {
    return v3{v.x, 0, v.y}
}

color_invert :: proc(c: rl.Color) -> rl.Color {
    return {255-c.r, 255-c.g, 255-c.b, c.a}
}

hex_color :: proc(c: u32) -> rl.Color {
    return {
        u8(c >> 16),
        u8(c >>  8),
        u8(c >>  0),
        255,
    }
}

// degrees
normalize_angle :: proc(angle: f32) -> f32 {
    return math.mod(angle + 36000, 360)
}

// degrees
angle_to_v2 :: proc(angle: f32) -> v2 {
    y, x := math.sincos(rl.DEG2RAD * angle)
    return v2{x, y}
}

// degrees
v2_to_angle :: proc(v: v2) -> f32 {
    return rl.RAD2DEG * math.atan2(v.y, v.x)
}

left_stick :: proc(id: c.int) -> v2 {
    return v2 {
        rl.GetGamepadAxisMovement(id, .LEFT_X),
        rl.GetGamepadAxisMovement(id, .LEFT_Y)
    }
}

right_stick :: proc(id: c.int) -> v2 {
    return v2 {
        rl.GetGamepadAxisMovement(id, .RIGHT_X),
        rl.GetGamepadAxisMovement(id, .RIGHT_Y)
    }
}

is_ctrl_down :: proc() -> bool {
    return rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
}