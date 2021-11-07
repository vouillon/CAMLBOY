open Camlboy_lib
open Brr
open Brr_canvas
open Brr_io
open Fut.Syntax


let gb_w = 160
let gb_h = 144

type rom_option = {name : string; path : string}
let rom_options = [
  {name = "The Bouncing Ball" ; path = "./the-bouncing-ball.gb"};
  {name = "Tobu Tobu Girl"    ; path =  "./tobu.gb"};
  {name = "Dreaming Sarah"    ; path =  "./dreaming-sarah.gb"};
]

let alert v =
  let alert = Jv.get Jv.global "alert" in
  ignore @@ Jv.apply alert Jv.[| of_string v |]

let find_el_by_id id = Document.find_el_by_id G.document (Jstr.v id) |> Option.get

let draw_framebuffer ctx image_data fb =
  let d = C2d.Image_data.data image_data in
  for y = 0 to gb_h - 1 do
    for x = 0 to gb_w - 1 do
      let off = 4 * (y * gb_w + x) in
      match fb.(y).(x) with
      | `White ->
        Tarray.set d (off    ) 0xE5;
        Tarray.set d (off + 1) 0xFB;
        Tarray.set d (off + 2) 0xF4;
        Tarray.set d (off + 3) 0xFF;
      | `Light_gray ->
        Tarray.set d (off    ) 0x97;
        Tarray.set d (off + 1) 0xAE;
        Tarray.set d (off + 2) 0xB8;
        Tarray.set d (off + 3) 0xFF;
      | `Dark_gray ->
        Tarray.set d (off    ) 0x61;
        Tarray.set d (off + 1) 0x68;
        Tarray.set d (off + 2) 0x7D;
        Tarray.set d (off + 3) 0xFF;
      | `Black ->
        Tarray.set d (off    ) 0x22;
        Tarray.set d (off + 1) 0x1E;
        Tarray.set d (off + 2) 0x31;
        Tarray.set d (off + 3) 0xFF;
    done
  done;
  C2d.put_image_data ctx image_data ~x:0 ~y:0

(** Manages state that need to be re-set when loading a new rom *)
module State = struct
  let run_id = ref None
  let key_down_listener = ref None
  let key_up_listener = ref None
  let set id down up =
    run_id := Some id;
    key_down_listener := Some down;
    key_up_listener := Some up
  let clear () =
    begin match !run_id with
      | None -> ()
      | Some timer_id ->
        G.stop_timer timer_id
    end;
    begin match !key_down_listener with
      | None -> ()
      | Some lister -> Ev.unlisten Ev.keydown lister G.target
    end;
    begin match !key_up_listener with
      | None -> ()
      | Some lister -> Ev.unlisten Ev.keyup lister G.target
    end;
end

let run_rom_bytes ctx image_data rom_bytes =
  State.clear ();
  let cartridge = Detect_cartridge.f ~rom_bytes in
  let module C = Camlboy.Make(val cartridge) in
  let t =  C.create_with_rom ~print_serial_port:true ~rom_bytes in
  let key_down_listener ev =
    let key_ev = Ev.as_type ev in
    let key_name = key_ev |> Ev.Keyboard.key |> Jstr.to_string in
    match key_name with
    | "Enter" -> C.press t Start
    | "Tab"   -> C.press t Select
    | "j"     -> C.press t B
    | "k"     -> C.press t A
    | "w"     -> C.press t Up
    | "a"     -> C.press t Left
    | "s"     -> C.press t Down
    | "d"     -> C.press t Right
    | _ -> ()
  in
  let key_up_listener ev =
    let key_ev = Ev.as_type ev in
    let key_name = key_ev |> Ev.Keyboard.key |> Jstr.to_string in
    match key_name with
    | "Enter" -> C.release t Start
    | "Tab"   -> C.release t Select
    | "j"     -> C.release t B
    | "k"     -> C.release t A
    | "w"     -> C.release t Up
    | "a"     -> C.release t Left
    | "s"     -> C.release t Down
    | "d"     -> C.release t Right
    | _ -> ()
  in
  Ev.listen Ev.keydown (key_down_listener) G.target;
  Ev.listen Ev.keyup (key_up_listener) G.target;
  let cnt = ref 0 in
  let start_time = ref (Performance.now_ms G.performance) in
  let set_fps fps =
    let fps_str = Printf.sprintf "%.2f" fps in
    let fps_el = find_el_by_id "fps" in
    El.set_children fps_el [El.txt (Jstr.v fps_str)]
  in
  let rec main_loop () =
    begin match C.run_instruction t with
      | In_frame ->
        main_loop ()
      | Frame_ended fb ->
        incr cnt;
        if !cnt = 60 then begin
          let end_time = Performance.now_ms G.performance in
          let sec_per_60_frame = (end_time -. !start_time) /. 1000. in
          let fps = 60. /.  sec_per_60_frame in
          start_time := end_time;
          set_fps fps;
          Console.(log [fps]);
          cnt := 0;
        end;
        draw_framebuffer ctx image_data fb;
    end;
  in
  let run_id = G.set_interval ~ms:1 main_loop in
  State.set run_id key_down_listener key_up_listener

let run_rom_blob ctx image_data rom_blob =
  let* result = Blob.array_buffer rom_blob in
  match result with
  | Ok buf ->
    let rom_bytes =
      Tarray.of_buffer Uint8 buf
      |> Tarray.to_bigarray1
      (* Convert uint8 bigarray to char bigarray *)
      |> Obj.magic
    in
    Fut.return @@ run_rom_bytes ctx image_data rom_bytes
  | Error e ->
    Fut.return @@ Console.(log [Jv.Error.message e])

let on_load_rom ctx image_data input_el =
  let file = El.Input.files input_el |> List.hd in
  let blob = File.as_blob file in
  Fut.await (run_rom_blob ctx image_data blob) (fun () -> ())

let run_selected_rom ctx image_data rom_path =
  let* result = Fetch.url (Jstr.v rom_path) in
  match result with
  | Ok response ->
    let body = Fetch.Response.as_body response in
    let* result = Fetch.Body.blob body in
    begin match result with
      | Ok blob -> run_rom_blob ctx image_data blob
      | Error e  -> Fut.return @@ Console.(log [Jv.Error.message e])
    end
  | Error e  -> Fut.return @@ Console.(log [Jv.Error.message e])

let set_up_rom_selector ctx image_data selector_el =
  rom_options
  |> List.map (fun rom_option ->
      El.option
        ~at:At.[value (Jstr.v rom_option.path)]
        [El.txt' rom_option.name])
  |> El.append_children selector_el;
  let on_change _ =
    let rom_path = El.prop (El.Prop.value) selector_el |> Jstr.to_string in
    Fut.await (run_selected_rom ctx image_data rom_path) (fun () -> ())
  in
  Ev.listen Ev.change on_change (El.as_target selector_el)

let () =
  (* Set up canvas *)
  let canvas = find_el_by_id "canvas" |> Canvas.of_el in
  let ctx = C2d.create canvas in
  C2d.scale ctx ~sx:1.5 ~sy:1.5;
  let image_data = C2d.create_image_data ctx ~w:gb_w ~h:gb_h in
  let fb = Array.make_matrix gb_h gb_w `Light_gray in
  draw_framebuffer ctx image_data fb;
  (* Set up load rom button *)
  let input_el = find_el_by_id "load-rom" in
  Ev.listen Ev.change (fun _ -> on_load_rom ctx image_data input_el) (El.as_target input_el);
  (* Set up rom selector *)
  let selector_el = find_el_by_id "rom-selector" in
  set_up_rom_selector ctx image_data selector_el;
  (* Load initial rom *)
  let rom = List.hd rom_options in
  let fut = run_selected_rom ctx image_data rom.path in
  Fut.await fut (fun () -> ())