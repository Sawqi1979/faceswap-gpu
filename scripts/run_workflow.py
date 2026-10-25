"""Build and run a ComfyUI ReActor video face-swap workflow against a local ComfyUI.
Reads node definitions from /object_info so input names always match the installed versions."""
import json, os, shutil, subprocess, sys, time, urllib.request

URL = "http://127.0.0.1:8188"
COMFY = "/work/ComfyUI"


def get(path):
    with urllib.request.urlopen(URL + path, timeout=60) as r:
        return json.loads(r.read())


def post(path, data):
    req = urllib.request.Request(URL + path, data=json.dumps(data).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def options(spec):
    t = spec[0]
    if isinstance(t, list):
        return t
    if t == "COMBO" and len(spec) > 1 and isinstance(spec[1], dict):
        return spec[1].get("options", [])
    return None


def default(spec):
    opts = options(spec)
    if len(spec) > 1 and isinstance(spec[1], dict) and "default" in spec[1]:
        return spec[1]["default"]
    if opts:
        return opts[0]
    return None


def pick(opts, *wants):
    for w in wants:
        for o in opts or []:
            if w.lower() in str(o).lower():
                return o
    return (opts or [None])[0]


def build(info, cls, overrides=None, links=None):
    overrides, links = overrides or {}, links or {}
    spec = info[cls]["input"]
    inputs = {}
    for name, s in spec.get("required", {}).items():
        if name in links:
            inputs[name] = links[name]
        elif name in overrides:
            inputs[name] = overrides[name]
        else:
            d = default(s)
            if d is not None:
                inputs[name] = d
    for name, s in spec.get("optional", {}).items():
        if name in links:
            inputs[name] = links[name]
        elif name in overrides:
            inputs[name] = overrides[name]
    return {"class_type": cls, "inputs": inputs}


def out_index(info, cls, type_name):
    outs = info[cls]["output"]
    return outs.index(type_name) if type_name in outs else None


def main():
    fps = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate",
                          "-of", "csv=p=0", f"{COMFY}/input/swap_input.mp4"], capture_output=True, text=True).stdout.strip()
    num, den = (fps.split("/") + ["1"])[:2]
    fps = round(float(num) / float(den or 1), 3) if num else 24
    info = get("/object_info")
    for need in ("VHS_LoadVideo", "VHS_VideoCombine", "LoadImage", "ReActorFaceSwap"):
        if need not in info:
            print("MISSING NODE", need); sys.exit(2)

    rf = info["ReActorFaceSwap"]["input"]
    allr = {**rf.get("required", {}), **rf.get("optional", {})}
    reactor_over = {"enabled": True}
    if "swap_model" in allr:
        reactor_over["swap_model"] = pick(options(allr["swap_model"]), "hyperswap_1b_256", "hyperswap_1a_256",
                                          "reswapper_256", "inswapper_128.onnx", "inswapper")
    if "facedetection" in allr:
        reactor_over["facedetection"] = pick(options(allr["facedetection"]), "retinaface_resnet50", "retinaface")
    if "face_restore_model" in allr:
        reactor_over["face_restore_model"] = pick(options(allr["face_restore_model"]), "GPEN-BFR-1024", "GPEN-BFR-512",
                                                  "codeformer", "GFPGANv1.4")
    if "face_restore_visibility" in allr:
        reactor_over["face_restore_visibility"] = 1.0
    if "codeformer_weight" in allr:
        reactor_over["codeformer_weight"] = 0.5
    print("ReActor settings:", reactor_over)
    boost = None
    if "ReActorFaceBoost" in info and "face_boost" in allr:
        bi = {**info["ReActorFaceBoost"]["input"].get("required", {}), **info["ReActorFaceBoost"]["input"].get("optional", {})}
        bo = {"enabled": True}
        if "boost_model" in bi:
            bo["boost_model"] = pick(options(bi["boost_model"]), "GPEN-BFR-1024", "GPEN-BFR-512", "codeformer", "GFPGANv1.4")
        if "interpolation" in bi:
            bo["interpolation"] = pick(options(bi["interpolation"]), "Lanczos", "Bicubic")
        if "visibility" in bi:
            bo["visibility"] = 1.0
        if "codeformer_weight" in bi:
            bo["codeformer_weight"] = 0.5
        if "restore_with_main_after" in bi:
            bo["restore_with_main_after"] = False
        boost = build(info, "ReActorFaceBoost", bo)
        print("Face boost:", bo)

    a_idx = out_index(info, "VHS_LoadVideo", "AUDIO")
    wf = {
        "1": build(info, "VHS_LoadVideo", {"video": "swap_input.mp4", "force_rate": 0, "frame_load_cap": 0,
                                            "skip_first_frames": 0, "select_every_nth": 1,
                                            "custom_width": 0, "custom_height": 0}),
        "2": build(info, "LoadImage", {"image": "swap_face.jpg"}),
    }
    links3 = {"input_image": ["1", 0], "source_image": ["2", 0]}
    if boost:
        wf["5"] = boost
        links3["face_boost"] = ["5", 0]
    wf["3"] = build(info, "ReActorFaceSwap", reactor_over, links3)
    combine_links = {"images": ["3", 0]}
    if a_idx is not None:
        combine_links["audio"] = ["1", a_idx]
    vc = info["VHS_VideoCombine"]["input"]["required"]
    wf["4"] = build(info, "VHS_VideoCombine",
                    {"frame_rate": fps, "loop_count": 0, "filename_prefix": "swap",
                     "format": pick(options(vc.get("format", ["x"])), "video/h264-mp4", "h264"),
                     "pingpong": False, "save_output": True, "crf": 17, "pix_fmt": "yuv420p"},
                    combine_links)
    print(json.dumps(wf, indent=1)[:3000])
    pid = post("/prompt", {"prompt": wf, "client_id": "riz-job"})
    if "prompt_id" not in pid:
        print("PROMPT REJECTED", pid); sys.exit(3)
    pid = pid["prompt_id"]
    print("queued", pid, flush=True)
    t0 = time.time()
    while time.time() - t0 < 40 * 60:
        h = get(f"/history/{pid}")
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                print("WORKFLOW ERROR", json.dumps(st)[:3000]); sys.exit(4)
            outs = h[pid].get("outputs", {})
            files = []
            for o in outs.values():
                for k in ("gifs", "videos", "images"):
                    files += o.get(k, [])
            vids = [f for f in files if str(f.get("filename", "")).endswith(".mp4")]
            if vids or st.get("completed"):
                if not vids:
                    print("NO VIDEO OUTPUT", json.dumps(outs)[:2000]); sys.exit(5)
                f = vids[-1]
                src = os.path.join(COMFY, f.get("type", "output"), f.get("subfolder", ""), f["filename"])
                os.makedirs("/work/out", exist_ok=True)
                shutil.copy(src, "/work/out/result.mp4")
                print("RESULT", src, os.path.getsize(src)); return
        time.sleep(5)
    print("TIMEOUT"); sys.exit(6)


if __name__ == "__main__":
    main()
