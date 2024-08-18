
package pirates

import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "core:math"
import "core:math/linalg"
import "core:math/rand"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

v2 :: [2]f32
v3 :: [3]f32
v4 :: [4]f32

GAME_TITLE :: "EPIC PIRATE GAME"

DEV :: #config(DEV, false)

WINDOW_WIDTH  :: 1280
WINDOW_HEIGHT :: 720

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

load_models :: proc($dir_path: string) -> map[string]rl.Model {
    model_files, match_err := filepath.glob(dir_path + "/*.gltf")
    assert(match_err == nil)

    result: map[string]rl.Model
    for path in model_files {
        free_all(context.temp_allocator)

        cpath := strings.clone_to_cstring(path, context.temp_allocator)

        model := rl.LoadModel(cpath)
        name := filepath.short_stem(path)
        
        if rl.IsModelReady(model) {
            result[name] = model
        }
    }

    return result
}

Game_State :: enum {
    Paused,
    Playing,

    // dev
    View_Models,
}

PLAYER_ENTITY_INDEX :: 0

entity_pos :: proc(v: v2) -> v3 {
    return v3{v.x, 0, v.y}
}

Entity :: struct {
    pos, vel, acc: v2,
    rot: f32,
    model: rl.Model,
}

Game :: struct {
    screen_width, screen_height: i32,

    state: Game_State,
    models: map[string]rl.Model,
    ocean: rl.Model,
    camera_xz_distance: f32,
    camera_xz_angle: f32,
    camera_y_height: f32,

    entities: [dynamic]Entity,

    // dev
    using dev: Dev_State,
}


OCEAN_LENGTH :: 1000
OCEAN_HEIGHT :: 5

game_init :: proc(game: ^Game) {
    game.screen_width = WINDOW_WIDTH
    game.screen_height = WINDOW_HEIGHT

    game.models = load_models("assets/models")

    game.ocean = rl.LoadModelFromMesh(rl.GenMeshCube(OCEAN_LENGTH, OCEAN_HEIGHT, OCEAN_LENGTH))

    image := rl.GenImagePerlinNoise(OCEAN_LENGTH, OCEAN_LENGTH*.5, 0, 0, 75)
    defer rl.UnloadImage(image)

    rl.ImageColorTint(&image, color_invert(hex_color(0x00EBFE)))
    rl.ImageColorInvert(&image)

    texture := rl.LoadTextureFromImage(image)
    rl.SetTextureFilter(texture, .TRILINEAR)

    game.ocean.materials[0].maps[0].texture = texture

    game.camera_xz_distance = 50
    game.camera_xz_angle = 45
    game.camera_y_height = 50

    game.entities = make([dynamic]Entity)

    // player entity
    append(&game.entities, Entity{
        model = game.models["Ship_Large"],
    })

    ENEMY_COUNT :: 100

    for _ in 0 ..< ENEMY_COUNT {
        entity: Entity
        entity.pos.x = rand.float32() * OCEAN_LENGTH - OCEAN_LENGTH*.5
        entity.pos.y = rand.float32() * OCEAN_LENGTH - OCEAN_LENGTH*.5
        entity.model = game.models["Ship_Large"]
        entity.rot = rand.float32() * 360

        append(&game.entities, entity)
    }

    game.state = .Playing

    when DEV {
        dev_init(&game.dev)
    }
}

SHIP_CONTROL_ACC :: 100
SHIP_CONTROL_TURN :: 100
SHIP_BRAKES_INV_COEFF :: 0.05
SHIP_MAX_VELOCITY :: 100

FORWARD_FRICTION_INV_COEFF :: 0.008
LATERAL_FRICTION_INV_COEFF :: 0.2



game_update_and_draw :: proc(game: ^Game, paused: bool) {
    dt := rl.GetFrameTime()

    player := &game.entities[PLAYER_ENTITY_INDEX]

    if !paused { // update
        e := player

        // TODO: update camera

        { // update player
            dir_x := rl.GetGamepadAxisMovement(0, .LEFT_X)
            dir_y := rl.GetGamepadAxisMovement(0, .LEFT_Y)

            sticks := v3{dir_x, 0, dir_y}
            target_mag := linalg.length(sticks)
            target_dir := linalg.normalize0(sticks)

            // rotation
            drot: f32
            if rl.IsKeyDown(.RIGHT) do drot -= SHIP_CONTROL_TURN
            if rl.IsKeyDown(.LEFT)  do drot += SHIP_CONTROL_TURN

            e.rot += drot * dt * max(linalg.length(e.vel) / SHIP_MAX_VELOCITY, 0.2)

            // movement in direction
            acc_mag: f32 = rl.IsKeyDown(.UP) ? SHIP_CONTROL_ACC : 0
            brakes: f32 = rl.IsKeyDown(.DOWN) ? SHIP_BRAKES_INV_COEFF : 0

            lateral_friction := linalg.dot(v2{-e.vel.y, e.vel.x}, e.vel) * LATERAL_FRICTION_INV_COEFF

            total_friction := brakes + FORWARD_FRICTION_INV_COEFF + lateral_friction

            e.vel *= 1 - total_friction

            dir_y, dir_x := math.sincos(rl.DEG2RAD * e.rot)
            acc := v2{-dir_x, dir_y} * acc_mag
            e.pos += dt*e.vel + 0.5*e.acc*dt*dt
            e.vel += 0.5*(e.acc + acc)*dt
            vel_mag := min(linalg.length(e.vel), SHIP_MAX_VELOCITY)
            e.vel = vel_mag*linalg.normalize0(e.vel)

            e.acc = acc
        }
    }

    camera_off_z, camera_off_x := math.sincos(rl.DEG2RAD * game.camera_xz_angle)
    camera_off_xz := v2{camera_off_x, camera_off_z}
    camera_off_xz *= game.camera_xz_distance
    camera_off := v3{camera_off_xz.x, game.camera_y_height, camera_off_xz.y}

    camera := rl.Camera {
        target = entity_pos(player.pos),
        position = entity_pos(player.pos) + camera_off,
        up = {0, 1, 0},
        fovy = 75,
        projection = .PERSPECTIVE,
    }

    { // draw
        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.SKYBLUE)

        {
            rl.BeginMode3D(camera)
            defer rl.EndMode3D()

            rl.DrawModel(game.ocean, {0, -.5*OCEAN_HEIGHT, 0}, 1, rl.WHITE)
            
            for e, i in game.entities {
                tint := i == PLAYER_ENTITY_INDEX ? rl.WHITE : rl.RED
                draw_pos := v3{e.pos.x, 0, e.pos.y}

                rl.DrawModelEx(e.model, draw_pos, {0, 1, 0}, e.rot, 1, tint)
            }

            when DEV {
                model := game.models["UI_Red_X"]
                dir_x := rl.GetGamepadAxisMovement(0, .LEFT_X)
                dir_y := rl.GetGamepadAxisMovement(0, .LEFT_Y)

                sticks := v3{dir_x, 0, dir_y}
                target_mag := linalg.length(sticks)
                target_dir := linalg.normalize0(sticks)

                target_spot := entity_pos(player.pos) + target_dir * (SHIP_MAX_VELOCITY * target_mag)

                rl.DrawModel(model, target_spot, 10, rl.WHITE)
            }
        }

        if paused {
            text :: "PAUSED"
            size :: 76

            width := rl.MeasureText(text, size)
            x := (game.screen_width - width)/2
            y := (game.screen_height - size)/2
            rl.DrawText(text, x, y, size, rl.PURPLE)
        }

        when DEV {
            rl.DrawFPS(5,5)
        }
    }
}

update_and_draw :: proc(game: ^Game) {
    switch game.state {
        case .Paused:      game_update_and_draw(game, true)
        case .Playing:     game_update_and_draw(game, false)
        case .View_Models: when DEV { view_models(game) }
    }
}

main :: proc() {
    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, GAME_TITLE)

    game := &Game{}
    game_init(game)

    rl.SetConfigFlags({.VSYNC_HINT, .MSAA_4X_HINT})
    
    // so the sails don't get culled out
    rlgl.DisableBackfaceCulling()

    rl.SetTargetFPS(rl.GetMonitorRefreshRate(rl.GetCurrentMonitor()))

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)

        when DEV {
            dev_state(game, .V, .View_Models)
        }

        if rl.IsKeyPressed(.P) {
            #partial switch game.state {
                case .Paused: game.state = .Playing
                case .Playing: game.state = .Paused
            }
        }

        update_and_draw(game)
    }
}
