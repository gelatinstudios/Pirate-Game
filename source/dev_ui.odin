
package pirates

import "core:fmt"
import "core:reflect"

import rl "vendor:raylib"
import mu "vendor:microui"

dev_ui_init :: proc(dev: ^Dev_State) {
	pixels := make([][4]u8, mu.DEFAULT_ATLAS_WIDTH*mu.DEFAULT_ATLAS_HEIGHT)
	for alpha, i in mu.default_atlas_alpha {
		pixels[i] = {0xff, 0xff, 0xff, alpha}
	}
	defer delete(pixels)
		
	image := rl.Image{
		data = raw_data(pixels),
		width   = mu.DEFAULT_ATLAS_WIDTH,
		height  = mu.DEFAULT_ATLAS_HEIGHT,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	dev.ui_texture = rl.LoadTextureFromImage(image)

	mu.init(&dev.ui)

	dev.ui.text_width = mu.default_atlas_text_width
	dev.ui.text_height = mu.default_atlas_text_height
}

dev_ui_input :: proc(ui: ^mu.Context) {
	// mouse coordinates
	mouse_pos := [2]i32{rl.GetMouseX(), rl.GetMouseY()}
	mu.input_mouse_move(ui, mouse_pos.x, mouse_pos.y)
	mu.input_scroll(ui, 0, i32(rl.GetMouseWheelMove() * -30))
	
	// mouse buttons
	@static buttons_to_key := [?]struct{
		rl_button: rl.MouseButton,
		mu_button: mu.Mouse,
	}{
		{.LEFT, .LEFT},
		{.RIGHT, .RIGHT},
		{.MIDDLE, .MIDDLE},
	}
	for button in buttons_to_key {
		if rl.IsMouseButtonPressed(button.rl_button) { 
			mu.input_mouse_down(ui, mouse_pos.x, mouse_pos.y, button.mu_button)
		} else if rl.IsMouseButtonReleased(button.rl_button) { 
			mu.input_mouse_up(ui, mouse_pos.x, mouse_pos.y, button.mu_button)
		}
		
	}
	
	// keyboard
	@static keys_to_check := [?]struct{
		rl_key: rl.KeyboardKey,
		mu_key: mu.Key,
	}{
		{.LEFT_SHIFT,    .SHIFT},
		{.RIGHT_SHIFT,   .SHIFT},
		{.LEFT_CONTROL,  .CTRL},
		{.RIGHT_CONTROL, .CTRL},
		{.LEFT_ALT,      .ALT},
		{.RIGHT_ALT,     .ALT},
		{.ENTER,         .RETURN},
		{.KP_ENTER,      .RETURN},
		{.BACKSPACE,     .BACKSPACE},
	}
	for key in keys_to_check {
		if rl.IsKeyPressed(key.rl_key) {
			mu.input_key_down(ui, key.mu_key)
		} else if rl.IsKeyReleased(key.rl_key) {
			mu.input_key_up(ui, key.mu_key)
		}
	}
}

dev_ui_reflect :: proc(ui: ^mu.Context, v: any, name: string, $is_header: bool) {
	value_label :: proc(ui: ^mu.Context, v: any, name: string) {
		mu.layout_row(ui, []i32{150,0,-1})
		mu.label(ui, fmt.tprint(name))
		mu.label(ui, "=")
		mu.label(ui, fmt.tprint(v))
	}

	base := reflect.type_info_base(type_info_of(v.id))

	if reflect.is_pointer(base) {
		if reflect.is_nil(v) {
			value_label(ui, v, name)
		} else {
			dev_ui_reflect(ui, reflect.deref(v), name, false)
		}
	} else if reflect.is_struct(base) || reflect.is_union(base) {
		mu.push_id(ui, uintptr(v.data))
		defer mu.pop_id(ui)

		if .ACTIVE in (is_header ? mu.header(ui, name) : mu.begin_treenode(ui, name)) {
			if reflect.is_union(base) {
				v := reflect.get_union_variant(v)
				name := fmt.tprint(v.id)
				dev_ui_reflect(ui, v, name, false)
			} else {
				for field_name in reflect.struct_field_names(v.id) {
					field := reflect.struct_field_value_by_name(v, field_name)
					dev_ui_reflect(ui, field, field_name, false)
				}
			}

			if !is_header do mu.end_treenode(ui)
		}
	} else if reflect.is_array(base) || reflect.is_dynamic_array(base) {
		array_len := reflect.length(v)
		if array_len < 10 {
			value_label(ui, v, name)
		} else {
			text := fmt.tprintf("{} (len={})", name, array_len)

			if .ACTIVE in mu.treenode(ui, text) {
				it := 0
				for e,i in reflect.iterate_array(v, &it) {
					dev_ui_reflect(ui, e, fmt.tprintf("[{}]", i), false)
				}
			}
		}
	} else if reflect.is_dynamic_map(base) {
		map_len := reflect.length(v)
		if map_len < 10 {
			value_label(ui, v, name)
		} else {
			text := fmt.tprintf("{} (len={})", name, map_len)

			if .ACTIVE in mu.treenode(ui, text) {
				it := 0
				for k,val in reflect.iterate_map(v, &it) {
					dev_ui_reflect(ui, val, fmt.tprintf("[{}]", k), false)
				}
			}
		}
	} else {
		value_label(ui, v, name)
	}
}

dev_ui :: proc(game: ^Game) {
	ui := &game.dev.ui

	mu.begin(ui)

	if mu.window(ui, "Dev UI", {30, 30, 300, 450}, {.NO_CLOSE}) {
		dev_ui_reflect(ui, game^, "Game", true)
	}

	mu.end(ui)

	dev_ui_render(&game.dev)
}

dev_ui_render :: proc(dev: ^Dev_State) {
	render_texture :: proc(dev: ^Dev_State, rect: mu.Rect, pos: [2]i32, color: mu.Color) {
        source := rl.Rectangle{f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}
        position := rl.Vector2{f32(pos.x), f32(pos.y)}

        rl.DrawTextureRec(dev.ui_texture, source, position, transmute(rl.Color)color)
    }

    rl.BeginScissorMode(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight())
    defer rl.EndScissorMode()

    command_backing: ^mu.Command
    for variant in mu.next_command_iterator(&dev.ui, &command_backing) {
        switch cmd in variant {
	        case ^mu.Command_Text:
	            pos := [2]i32{cmd.pos.x, cmd.pos.y}
	            for ch in cmd.str do if ch & 0xc0 != 0x80 {
                    r := min(int(ch), 127)
                    rect := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
                    render_texture(dev, rect, pos, cmd.color)
                    pos.x += rect.w
	            }

	        case ^mu.Command_Rect:
	            rl.DrawRectangle(expand_values(cmd.rect), transmute(rl.Color) cmd.color)

	        case ^mu.Command_Icon:
	            rect := mu.default_atlas[cmd.id]
	            x := cmd.rect.x + (cmd.rect.w - rect.w) / 2
	            y := cmd.rect.y + (cmd.rect.h - rect.h) / 2
	            render_texture(dev, rect, {x, y}, cmd.color)

	        case ^mu.Command_Clip:
	            rl.EndScissorMode()
	            rl.BeginScissorMode(cmd.rect.x, rl.GetScreenHeight() - (cmd.rect.y + cmd.rect.h), cmd.rect.w, cmd.rect.h)

	        case ^mu.Command_Jump: unreachable()
	        case:                  unreachable()
        }
    }
}