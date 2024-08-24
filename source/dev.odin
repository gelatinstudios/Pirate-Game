
package pirates

import "core:strings"
import rl "vendor:raylib"
import mu "vendor:microui"

when DEV {
    Dev_State :: struct {
        prev_state: Game_State,
        view_models_camera: rl.Camera,

        show_ui: bool,
        ui: mu.Context,
        ui_texture: rl.Texture2D,
    }


    dev_init :: proc(dev: ^Dev_State) {
        dev.view_models_camera = {
            target = {},
            position = {0, 10, 50},
            up = {0, 1, 0},
            projection = .PERSPECTIVE,
            fovy = 75,
        }
        dev_ui_init(dev)
    }

    dev_state :: proc(game: ^Game, key: rl.KeyboardKey, state: Game_State) {
        if is_ctrl_down() && rl.IsKeyPressed(key) {
            if game.state == state {
                game.state = game.prev_state
            } else {
                game.prev_state = game.state
                game.state = state
            }
        }
    }


    view_models :: proc(game: ^Game) {
        camera := &game.view_models_camera

        rl.UpdateCamera(camera, .FREE)

        {
            rl.BeginDrawing()

            rl.ClearBackground(rl.SKYBLUE)

            Text :: struct {
                text: cstring,
                x, y: i32,
            }

            texts := make([]Text, len(game.models), allocator=context.temp_allocator)
            text_index := 0

            {
                rl.BeginMode3D(camera^)
                defer rl.EndMode3D()

                columns := 12
                rows := len(game.models) / columns

                COLUMN_WIDTH :: 10
                COLUMN_HEIGHT :: 10

                x := (-columns / 2) * COLUMN_WIDTH
                y := (-rows / 2)    * COLUMN_HEIGHT
                column_count := 0
                for name, model in game.models {
                    pos := v3{f32(x), 0, f32(y)}
                    rl.DrawModel(model, pos, 1, rl.WHITE)

                    column_count += 1
                    if column_count == columns {
                        column_count = 0
                        x = (-columns / 2) * COLUMN_WIDTH
                        y += COLUMN_HEIGHT
                    } else {
                        x += COLUMN_WIDTH
                    }

                    bb := rl.GetModelBoundingBox(model)
                    height := bb.max.y - bb.min.y

                    text_world_pos := pos + v3{0, height, 0}
                    text_screen_pos := rl.GetWorldToScreen(text_world_pos, camera^)

                    if rl.CheckCollisionPointRec(text_screen_pos, {0,0,f32(game.screen_width), f32(game.screen_height)}) {
                        texts[text_index] = Text {
                            text = strings.clone_to_cstring(name, context.temp_allocator),
                            x = i32(text_screen_pos.x),
                            y = i32(text_screen_pos.y),
                        }
                        text_index += 1
                    }
                }
            }

            for text in texts[:text_index] {
                rl.DrawText(text.text, text.x, text.y, 12, rl.BLACK)
            }

            rl.DrawFPS(5, 5)
        }
    }
} else {
    Dev_State :: struct{}
}
