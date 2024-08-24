
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

Entity :: struct {
    pos, vel, acc, prev_acc: v2,
    rot: f32,
    brain: Enemy_Brain,
    model: rl.Model,
}

Enemy_Brain :: struct {
    input: v3,
    timer: f32,
}

Game :: struct {
    screen_width, screen_height: i32,

    models: map[string]rl.Model,
    ocean: rl.Model,
    camera_xz_distance: f32,
    camera_xz_angle: f32,
    camera_y_height: f32,

    state: Game_State,
    player_is_aiming: bool,
    entities: [dynamic]Entity,

    // indices
    player_index: int,
    enemy_start: int,
    enemy_end: int,

    // dev
    using dev: Dev_State,
}


OCEAN_EXTENT :: 1000
OCEAN_LENGTH :: OCEAN_EXTENT * 2
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
    game.player_index = len(game.entities)
    append(&game.entities, Entity{
        model = game.models["Ship_Large"],
    })

    ENEMY_COUNT :: 100

    game.enemy_start = len(game.entities)
    for _ in 0 ..< ENEMY_COUNT {
        entity: Entity
        entity.pos.x = rand.float32() * OCEAN_LENGTH - OCEAN_LENGTH*.5
        entity.pos.y = rand.float32() * OCEAN_LENGTH - OCEAN_LENGTH*.5
        entity.model = game.models["Ship_Large"]
        entity.rot = rand.float32() * 360

        append(&game.entities, entity)
    }
    game.enemy_end = len(game.entities)

    game.state = .Playing

    when DEV {
        dev_init(&game.dev)
    }
}

get_player :: proc(game: ^Game) -> ^Entity {
    return &game.entities[game.player_index]
}
get_camera_pos :: proc(game: ^Game) -> v3 {
    camera_off_xz := angle_to_v2(game.camera_xz_angle) * game.camera_xz_distance
    return expand_to_v3(get_player(game).pos) + v3{camera_off_xz.x, game.camera_y_height, camera_off_xz.y}
}

create_cannon_entity :: proc(ship: Entity) -> Entity {
    // TODO:
    return {}
}

SHIP_CONTROL_ACC :: 100
SHIP_CONTROL_TURN_COEFF :: 0.8
SHIP_BRAKES_INV_COEFF :: 0.05
SHIP_MAX_VELOCITY :: 100

FORWARD_FRICTION_INV_COEFF :: 0.02

CAMERA_XZ_VEL :: 100
CAMERA_Y_VEL :: 5
CAMERA_FOV :: 75

ship_move :: proc(e: ^Entity, input: v3, brakes: bool) {
    dt := rl.GetFrameTime()

    input_mag := linalg.length(input)
    input_dir := linalg.normalize0(input)
    input_angle := v2_to_angle(input.xz)

    // rotation
    if input_mag > 0 {
        d_rot := input_angle - e.rot
        d_rot = normalize_angle(d_rot+180)-180
        e.rot += SHIP_CONTROL_TURN_COEFF * dt * d_rot
        e.rot = normalize_angle(e.rot)
    }      

    ship_dir := angle_to_v2(e.rot)

    // friction
    acc_mag: f32 = linalg.dot(input_mag * input_dir, expand_to_v3(ship_dir))  * SHIP_CONTROL_ACC
    brakes_friction: f32 = brakes ? SHIP_BRAKES_INV_COEFF : 0
    lateral_friction := linalg.dot(v2{-e.vel.y, e.vel.x}, e.vel)
    total_friction := brakes_friction + FORWARD_FRICTION_INV_COEFF + lateral_friction
    e.vel *= 1 - total_friction

    e.acc = ship_dir * acc_mag
}

game_update_and_draw :: proc(game: ^Game, paused: bool) {
    dt := rl.GetFrameTime()

    player := &game.entities[game.player_index ]

    target_mag: f32
    target_dir: v3
    target_angle: f32

    if !paused { // update
        e := player

        // cannon fire
        player_fired_cannon: bool
        if rl.IsGamepadButtonDown(0, .RIGHT_TRIGGER_2) {
            game.player_is_aiming = true
        } else {
            player_fired_cannon = game.player_is_aiming
            game.player_is_aiming = false
        }
        if player_fired_cannon {
            append(&game.entities, create_cannon_entity(player^))
        }

        if !game.player_is_aiming {// update camera
            game.camera_xz_angle += rl.GetGamepadAxisMovement(0, .RIGHT_X) * CAMERA_XZ_VEL * dt
            game.camera_y_height += -rl.GetGamepadAxisMovement(0, .RIGHT_Y) * CAMERA_XZ_VEL * dt

            game.camera_xz_angle = normalize_angle(game.camera_xz_angle)
            game.camera_y_height = max(game.camera_y_height, 2)
        }

        raw_input := left_stick(0)

        input_mag := linalg.length(raw_input)

        input_angle := v2_to_angle(raw_input)
        input_angle += game.camera_xz_angle - 90
        input_angle = normalize_angle(input_angle)

        input := expand_to_v3(angle_to_v2(input_angle)) * input_mag

        ship_move(player, input, rl.IsGamepadButtonDown(0, .RIGHT_TRIGGER_1))

        for &e in game.entities[game.enemy_start:game.enemy_end] {
            b := &e.brain
            b.timer -= dt
            if b.timer <= 0 {
                input: v3
                for &f in input {
                    f = rand.float32() * 2 - 1
                }
                b.input = linalg.normalize0(input) * rand.float32()
                b.timer = 5
            }
            ship_move(&e, b.input, false)
        }

        // collision
        for &e in game.entities[game.player_index:game.enemy_end] {
            out_of_bounds := false
            for f in e.pos {
                out_of_bounds ||= abs(f) > OCEAN_EXTENT
            }

            if out_of_bounds {
                e.acc = 0
                e.vel = 0
            }
        }

        // movement update
        for &e in game.entities {
            e.pos += dt*e.vel + 0.5*e.acc*dt*dt
            e.vel += 0.5*(e.acc + e.prev_acc)*dt

            // TODO: not everything is a ship
            // clamp velocity megnitude
            vel_mag := min(linalg.length(e.vel), SHIP_MAX_VELOCITY)
            e.vel = vel_mag*linalg.normalize0(e.vel)

            e.prev_acc = e.acc
        }
    }

    camera := rl.Camera {
        target = expand_to_v3(player.pos),
        position = get_camera_pos(game),
        up = {0, 1, 0},
        fovy = CAMERA_FOV,
        projection = .PERSPECTIVE,
    }

    { // draw
        rl.BeginDrawing() // DOES NOT call EndDrawing()

        rl.ClearBackground(rl.SKYBLUE)

        {
            rl.BeginMode3D(camera)
            defer rl.EndMode3D()

            rl.DrawModel(game.ocean, {0, -.5*OCEAN_HEIGHT, 0}, 1, rl.WHITE)
            
            for e, i in game.entities {
                tint := i == game.player_index ? rl.WHITE : rl.RED
                draw_pos := v3{e.pos.x, 0, e.pos.y}

                rl.DrawModelEx(e.model, draw_pos, {0, -1, 0}, e.rot + 180, 1, tint)
            }

            if false && DEV && target_mag > 0 {
                model := game.models["UI_Red_X"]
                target_spot := expand_to_v3(player.pos) + target_dir * (SHIP_MAX_VELOCITY * target_mag)
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


    }
}

update_and_draw :: proc(game: ^Game) {
    switch game.state {
        case .Paused:      game_update_and_draw(game, true)
        case .Playing:     game_update_and_draw(game, false)
        case .View_Models: when DEV { view_models(game) }
    }

    when DEV {
        if game.dev.show_ui do dev_ui(game)
        rl.DrawFPS(5,5)
    }

    // putting this here allows us to add extra things like debug ui, editor, etc.
    rl.EndDrawing()
}

main :: proc() {
    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, GAME_TITLE)

    game := &Game{}
    game_init(game)

    rl.SetConfigFlags({.VSYNC_HINT, .MSAA_4X_HINT})
    
    when !DEV { 
        // by default, raylib uses ESC for exit
        // i like this for developing, but not for users
        rl.SetExitKey(nil)
    }

    // so the sails don't get culled out
    rlgl.DisableBackfaceCulling()

    rl.SetTargetFPS(rl.GetMonitorRefreshRate(rl.GetCurrentMonitor()))

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)

        when DEV {
            dev_state(game, .V, .View_Models)

            if is_ctrl_down() && rl.IsKeyPressed(.M) {
                game.dev.show_ui = !game.dev.show_ui
            }

            if game.dev.show_ui {
                dev_ui_input(&game.dev.ui)
            }
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
