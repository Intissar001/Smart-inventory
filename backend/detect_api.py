from fastapi import FastAPI, File, UploadFile, Form
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO
import shutil
import os
import cv2
from PIL import Image
import uvicorn
import io
import json

app = FastAPI(title="Smart Inventory API", version="2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

MODEL_PATH = "best.pt"
if not os.path.exists(MODEL_PATH):
    print(f"⚠️ Fichier {MODEL_PATH} non trouvé!")
    model = None
    class_names = {}
else:
    model = YOLO(MODEL_PATH)
    class_names = model.names
    print(f"✅ Modèle chargé: {MODEL_PATH}")
    print(f"🏷️ Classes: {class_names}")


@app.get("/")
async def root():
    return {"message": "Smart Inventory API", "status": "running"}


@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": model is not None}


@app.post("/detect")
async def detect(file: UploadFile = File(...)):
    """
    Detect medicine boxes in an image.
    Returns bounding boxes [x1, y1, x2, y2] in original image pixel coordinates.
    """
    if model is None:
        return JSONResponse(
            status_code=500,
            content={"success": False, "error": "Modèle non chargé"}
        )

    temp_path = "temp_image.jpg"

    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        img = cv2.imread(temp_path)
        if img is None:
            pil_img = Image.open(temp_path)
            height, width = pil_img.size[1], pil_img.size[0]
        else:
            height, width = img.shape[:2]

        print(f"📷 Image reçue: {width}x{height}")

        results = model(temp_path)

        detections = []
        if results and len(results) > 0 and results[0].boxes is not None:
            for i, box in enumerate(results[0].boxes):
                class_id = int(box.cls[0])
                confidence = float(box.conf[0])
                bbox = box.xyxy[0].tolist()  # [x1, y1, x2, y2] in pixels

                x1, y1, x2, y2 = bbox
                box_width = x2 - x1
                box_height = y2 - y1

                detections.append({
                    "id": i,
                    "class": class_id,
                    "label": class_names.get(class_id, f"Class_{class_id}"),
                    "confidence": round(confidence, 4),
                    # Pixel coords — use these for cropping
                    "bbox": [round(x1), round(y1), round(x2), round(y2)],
                    # Normalized coords [0..1] — optional, useful for Flutter scaling
                    "bbox_norm": [
                        round(x1 / width, 6),
                        round(y1 / height, 6),
                        round(x2 / width, 6),
                        round(y2 / height, 6),
                    ],
                    "box_width_px": round(box_width),
                    "box_height_px": round(box_height),
                })

        print(f"✅ {len(detections)} objets détectés")

        os.remove(temp_path)

        return JSONResponse({
            "success": True,
            "detections": detections,
            "count": len(detections),
            "image_width": width,
            "image_height": height,
        })

    except Exception as e:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        print(f"❌ Erreur: {e}")
        return JSONResponse(
            status_code=500,
            content={"success": False, "error": str(e)}
        )


@app.post("/crop")
async def crop(
    file: UploadFile = File(...),
    bbox: str = Form(...),          # JSON string: "[x1, y1, x2, y2]"
    padding: int = Form(default=4), # optional padding in pixels
):
    """
    Crop a single medicine box from an image.
    Send the original image + one bbox [x1, y1, x2, y2].
    Returns the cropped image as JPEG bytes.

    Flutter usage:
        var request = http.MultipartRequest('POST', Uri.parse('$base/crop'));
        request.files.add(await http.MultipartFile.fromPath('file', imagePath));
        request.fields['bbox'] = jsonEncode([x1, y1, x2, y2]);
        final response = await request.send();
        final bytes = await response.stream.toBytes();
        // bytes is the JPEG crop — save to disk or display with Image.memory
    """
    temp_path = "temp_crop.jpg"

    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        coords = json.loads(bbox)
        x1, y1, x2, y2 = [int(c) for c in coords[:4]]

        img = cv2.imread(temp_path)
        if img is None:
            pil_img = Image.open(temp_path).convert("RGB")
            img_h, img_w = pil_img.size[1], pil_img.size[0]
            # Apply padding and clamp
            x1 = max(0, x1 - padding)
            y1 = max(0, y1 - padding)
            x2 = min(img_w, x2 + padding)
            y2 = min(img_h, y2 + padding)
            crop_img = pil_img.crop((x1, y1, x2, y2))
            buf = io.BytesIO()
            crop_img.save(buf, format="JPEG", quality=95)
            jpeg_bytes = buf.getvalue()
        else:
            img_h, img_w = img.shape[:2]
            x1 = max(0, x1 - padding)
            y1 = max(0, y1 - padding)
            x2 = min(img_w, x2 + padding)
            y2 = min(img_h, y2 + padding)
            crop_img = img[y1:y2, x1:x2]
            _, buf = cv2.imencode(".jpg", crop_img, [cv2.IMWRITE_JPEG_QUALITY, 95])
            jpeg_bytes = buf.tobytes()

        os.remove(temp_path)

        print(f"✂️ Crop [{x1},{y1},{x2},{y2}] → {x2-x1}x{y2-y1}px")
        return Response(content=jpeg_bytes, media_type="image/jpeg")

    except Exception as e:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        print(f"❌ Crop error: {e}")
        return JSONResponse(
            status_code=500,
            content={"success": False, "error": str(e)}
        )


@app.post("/crop_all")
async def crop_all(file: UploadFile = File(...)):
    """
    Detect all boxes AND return each crop as base64.
    Useful when you want detection + crops in a single round-trip.
    Returns JSON with detections[] each having a 'crop_b64' field (JPEG base64).
    """
    import base64

    if model is None:
        return JSONResponse(
            status_code=500,
            content={"success": False, "error": "Modèle non chargé"}
        )

    temp_path = "temp_cropall.jpg"

    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        img_bgr = cv2.imread(temp_path)
        if img_bgr is None:
            return JSONResponse(status_code=400, content={"success": False, "error": "Impossible de lire l'image"})

        height, width = img_bgr.shape[:2]
        results = model(temp_path)

        detections = []
        if results and len(results) > 0 and results[0].boxes is not None:
            for i, box in enumerate(results[0].boxes):
                class_id = int(box.cls[0])
                confidence = float(box.conf[0])
                bbox = box.xyxy[0].tolist()
                x1, y1, x2, y2 = [int(c) for c in bbox]

                # Crop with small padding
                pad = 4
                cx1 = max(0, x1 - pad)
                cy1 = max(0, y1 - pad)
                cx2 = min(width, x2 + pad)
                cy2 = min(height, y2 + pad)
                crop = img_bgr[cy1:cy2, cx1:cx2]

                _, buf = cv2.imencode(".jpg", crop, [cv2.IMWRITE_JPEG_QUALITY, 90])
                crop_b64 = base64.b64encode(buf.tobytes()).decode("utf-8")

                detections.append({
                    "id": i,
                    "class": class_id,
                    "label": class_names.get(class_id, f"Class_{class_id}"),
                    "confidence": round(confidence, 4),
                    "bbox": [x1, y1, x2, y2],
                    "bbox_norm": [
                        round(x1 / width, 6),
                        round(y1 / height, 6),
                        round(x2 / width, 6),
                        round(y2 / height, 6),
                    ],
                    "crop_b64": crop_b64,  # JPEG base64 of this box
                })

        os.remove(temp_path)
        print(f"✅ crop_all: {len(detections)} boxes")

        return JSONResponse({
            "success": True,
            "detections": detections,
            "count": len(detections),
            "image_width": width,
            "image_height": height,
        })

    except Exception as e:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        print(f"❌ crop_all error: {e}")
        return JSONResponse(
            status_code=500,
            content={"success": False, "error": str(e)}
        )


if __name__ == "__main__":
    print("🚀 Démarrage du serveur Smart Inventory v2...")
    print("📍 Endpoints:")
    print("   POST /detect      → détection + bbox pixel coords")
    print("   POST /crop        → crop d'une seule boîte (multipart: file + bbox JSON)")
    print("   POST /crop_all    → détection + tous les crops en base64")
    print("📱 Android emulator: http://10.0.2.2:8000")
    import os
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)