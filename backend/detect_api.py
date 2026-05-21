from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO
import shutil
import os
import cv2
from PIL import Image
import uvicorn

app = FastAPI(title="Smart Inventory API", version="1.0")

# CORS pour Flutter - IMPORTANT
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Pour développement
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Charger modèle YOLO
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
    if model is None:
        return JSONResponse(
            status_code=500,
            content={"success": False, "error": "Modèle non chargé"}
        )

    temp_path = "temp_image.jpg"

    try:
        # Sauvegarder l'image
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # Lire l'image pour dimensions
        img = cv2.imread(temp_path)
        if img is None:
            pil_img = Image.open(temp_path)
            height, width = pil_img.size[1], pil_img.size[0]
        else:
            height, width = img.shape[:2]

        print(f"📷 Image reçue: {width}x{height}")

        # Inférence YOLO
        results = model(temp_path)

        detections = []
        if results and len(results) > 0 and results[0].boxes is not None:
            for box in results[0].boxes:
                class_id = int(box.cls[0])
                confidence = float(box.conf[0])
                bbox = box.xyxy[0].tolist()
                label = class_names.get(class_id, f"Class_{class_id}")

                detections.append({
                    "class": class_id,
                    "label": label,
                    "confidence": confidence,
                    "bbox": bbox
                })

        print(f"✅ {len(detections)} objets détectés")

        # Nettoyer
        os.remove(temp_path)

        return JSONResponse({
            "success": True,
            "detections": detections,
            "count": len(detections),
            "image_width": width,
            "image_height": height
        })

    except Exception as e:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        print(f"❌ Erreur: {e}")
        return JSONResponse(
            status_code=500,
            content={"success": False, "error": str(e)}
        )

if __name__ == "__main__":
    print("🚀 Démarrage du serveur Smart Inventory...")
    print("📍 Serveur accessible sur:")
    print("   - http://localhost:8000")
    print("   - http://127.0.0.1:8000")
    print("📱 Pour émulateur Android: http://10.0.2.2:8000")
    print("")
    uvicorn.run(app, host="0.0.0.0", port=8000)