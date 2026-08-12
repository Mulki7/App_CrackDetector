"""
train_model.py
Training CNN MobileNetV2 (Transfer Learning) untuk klasifikasi
citra candling telur ayam: Utuh vs Retak.

PENTING: Split dilakukan PER TELUR (bukan per foto) untuk mencegah
data leakage. Semua foto dari telur yang sama (berbagai sisi) akan
selalu berada di subset yang sama (train, val, ATAU test).

Cara pakai:
1. Taruh foto di:
   dataset/Utuh/*.jpg   (nama file harus diawali ID telur, misal "telur001_sisi1.jpg")
   dataset/Retak/*.jpg
2. Jalankan: python train_model.py
3. Output akan tersimpan di folder outputs/ dan model/
   - model/egg_classifier.h5      -> model Keras
   - model/egg_classifier.tflite  -> model untuk Flutter
   - outputs/history.json         -> untuk grafik accuracy/loss di Streamlit
   - outputs/eval_results.json    -> confusion matrix, classification report, sample prediksi test set
   - outputs/class_indices.json   -> mapping label
"""

import os
import re
import json
import random
import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow.keras.applications import MobileNetV2
from tensorflow.keras.applications.mobilenet_v2 import preprocess_input
from tensorflow.keras.layers import GlobalAveragePooling2D, Dense, Dropout
from tensorflow.keras.models import Model
from tensorflow.keras.optimizers import Adam
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from tensorflow.keras.preprocessing.image import ImageDataGenerator
from sklearn.model_selection import GroupShuffleSplit
from sklearn.metrics import confusion_matrix, classification_report
from sklearn.utils.class_weight import compute_class_weight

# ------------------------------------------------------------------
# KONFIGURASI
# ------------------------------------------------------------------
DATASET_DIR = "dataset"          # folder dataset/Utuh, dataset/Retak
IMG_SIZE = 224
BATCH_SIZE = 32
EPOCHS = 50
LEARNING_RATE = 1e-4
SEED = 42
TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
TEST_RATIO = 0.15                # sisanya

MODEL_DIR = "model"
OUTPUT_DIR = "outputs"
os.makedirs(MODEL_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)

random.seed(SEED)
np.random.seed(SEED)
tf.random.set_seed(SEED)

CLASS_NAMES = ["Utuh", "Retak"]   # 0 = Utuh, 1 = Retak

# ------------------------------------------------------------------
# 1. KUMPULKAN FILE PATH + LABEL
# ------------------------------------------------------------------
def collect_filepaths():
    rows = []
    for label in CLASS_NAMES:
        folder = os.path.join(DATASET_DIR, label)
        if not os.path.isdir(folder):
            raise FileNotFoundError(f"Folder tidak ditemukan: {folder}")
        for fname in os.listdir(folder):
            if fname.lower().endswith((".jpg", ".jpeg", ".png")):
                rows.append({
                    "filepath": os.path.join(folder, fname),
                    "label": label
                })
    df = pd.DataFrame(rows)
    if df.empty:
        raise ValueError("Tidak ada foto ditemukan di dataset/Utuh atau dataset/Retak.")
    return df

df = collect_filepaths()
print(f"Total citra ditemukan: {len(df)}")
print(df["label"].value_counts())

# ------------------------------------------------------------------
# 2. EKSTRAK ID TELUR DARI NAMA FILE
#    Contoh: "telur001_sisi1.jpg" -> "telur001"
#    Jika format nama file berbeda, sesuaikan regex di bawah.
# ------------------------------------------------------------------
def extract_egg_id(filepath):
    fname = os.path.basename(filepath)
    match = re.match(r"(telur\d+)", fname, re.IGNORECASE)
    if match:
        return match.group(1).lower()
    # fallback: kalau nama file tidak sesuai pola, anggap tiap file
    # sebagai telur tersendiri (lebih aman daripada salah kelompok)
    print(f"[PERINGATAN] Nama file tidak sesuai pola 'telurXXX...': {fname}")
    return fname

df["egg_id"] = df["filepath"].apply(extract_egg_id)
print(f"\nJumlah foto      : {len(df)}")
print(f"Jumlah telur unik: {df['egg_id'].nunique()}")
print("Jumlah telur unik per kelas:")
print(df.groupby("label")["egg_id"].nunique())

# ------------------------------------------------------------------
# 3. SPLIT PER TELUR (70/15/15) — mencegah data leakage
#    Semua foto dari egg_id yang sama pasti masuk subset yang sama.
#    Catatan: GroupShuffleSplit tidak bisa stratify per label,
#    jadi rasio kelas antar subset dilaporkan apa adanya (dicetak di bawah),
#    bukan dipaksa presisi 70:15:15 per kelas.
# ------------------------------------------------------------------
gss1 = GroupShuffleSplit(n_splits=1, test_size=(1 - TRAIN_RATIO), random_state=SEED)
train_idx, temp_idx = next(gss1.split(df, groups=df["egg_id"]))
train_df, temp_df = df.iloc[train_idx].reset_index(drop=True), df.iloc[temp_idx].reset_index(drop=True)

val_ratio_of_temp = VAL_RATIO / (VAL_RATIO + TEST_RATIO)
gss2 = GroupShuffleSplit(n_splits=1, test_size=(1 - val_ratio_of_temp), random_state=SEED)
val_idx, test_idx = next(gss2.split(temp_df, groups=temp_df["egg_id"]))
val_df, test_df = temp_df.iloc[val_idx].reset_index(drop=True), temp_df.iloc[test_idx].reset_index(drop=True)

# Sanity check: pastikan tidak ada egg_id yang bocor lintas subset
train_eggs, val_eggs, test_eggs = set(train_df["egg_id"]), set(val_df["egg_id"]), set(test_df["egg_id"])
assert not (train_eggs & val_eggs), "Data leakage terdeteksi antara Train dan Val!"
assert not (train_eggs & test_eggs), "Data leakage terdeteksi antara Train dan Test!"
assert not (val_eggs & test_eggs), "Data leakage terdeteksi antara Val dan Test!"
print("\n[OK] Tidak ada kebocoran ID telur antar subset (Train/Val/Test terpisah bersih).")

print(f"\nTrain: {len(train_df)} foto dari {train_df['egg_id'].nunique()} telur")
print(f"Val:   {len(val_df)} foto dari {val_df['egg_id'].nunique()} telur")
print(f"Test:  {len(test_df)} foto dari {test_df['egg_id'].nunique()} telur")
print("\nDistribusi kelas - Train:\n", train_df["label"].value_counts())
print("Distribusi kelas - Val:\n", val_df["label"].value_counts())
print("Distribusi kelas - Test:\n", test_df["label"].value_counts())

# ------------------------------------------------------------------
# 4. DATA GENERATOR
#    Augmentasi HANYA di train. Val/Test murni asli (preprocess only).
# ------------------------------------------------------------------
train_datagen = ImageDataGenerator(
    preprocessing_function=preprocess_input,
    rotation_range=25,
    width_shift_range=0.1,
    height_shift_range=0.1,
    brightness_range=[0.8, 1.2],
    zoom_range=0.15,
    horizontal_flip=True,
    fill_mode="nearest",
)

val_test_datagen = ImageDataGenerator(preprocessing_function=preprocess_input)

train_gen = train_datagen.flow_from_dataframe(
    train_df, x_col="filepath", y_col="label",
    target_size=(IMG_SIZE, IMG_SIZE), batch_size=BATCH_SIZE,
    class_mode="binary", classes=CLASS_NAMES, shuffle=True, seed=SEED
)
val_gen = val_test_datagen.flow_from_dataframe(
    val_df, x_col="filepath", y_col="label",
    target_size=(IMG_SIZE, IMG_SIZE), batch_size=BATCH_SIZE,
    class_mode="binary", classes=CLASS_NAMES, shuffle=False
)
test_gen = val_test_datagen.flow_from_dataframe(
    test_df, x_col="filepath", y_col="label",
    target_size=(IMG_SIZE, IMG_SIZE), batch_size=BATCH_SIZE,
    class_mode="binary", classes=CLASS_NAMES, shuffle=False
)

# simpan mapping label (0/1 -> nama kelas) untuk dipakai Streamlit
with open(os.path.join(OUTPUT_DIR, "class_indices.json"), "w") as f:
    json.dump(train_gen.class_indices, f, indent=2)

# ------------------------------------------------------------------
# 5. CLASS WEIGHT (menangani imbalance, dihitung otomatis dari data aktual)
# ------------------------------------------------------------------
train_labels = train_df["label"].map(train_gen.class_indices).values
class_weights_arr = compute_class_weight(
    class_weight="balanced",
    classes=np.unique(train_labels),
    y=train_labels
)
class_weight_dict = {i: w for i, w in enumerate(class_weights_arr)}
print("\nClass weights:", class_weight_dict)

# ------------------------------------------------------------------
# 6. BANGUN MODEL: MobileNetV2 + Transfer Learning
# ------------------------------------------------------------------
base_model = MobileNetV2(
    input_shape=(IMG_SIZE, IMG_SIZE, 3),
    include_top=False,
    weights="imagenet"
)
base_model.trainable = False  # freeze base -> transfer learning murni

x = base_model.output
x = GlobalAveragePooling2D()(x)
x = Dense(128, activation="relu")(x)
x = Dropout(0.3)(x)
output = Dense(1, activation="sigmoid")(x)

model = Model(inputs=base_model.input, outputs=output)
model.compile(
    optimizer=Adam(learning_rate=LEARNING_RATE),
    loss="binary_crossentropy",
    metrics=["accuracy"]
)
model.summary()

# ------------------------------------------------------------------
# 7. TRAINING
# ------------------------------------------------------------------
callbacks = [
    EarlyStopping(monitor="val_loss", patience=8, restore_best_weights=True),
    ModelCheckpoint(
        os.path.join(MODEL_DIR, "egg_classifier_best.h5"),
        monitor="val_accuracy", save_best_only=True
    ),
]

history = model.fit(
    train_gen,
    validation_data=val_gen,
    epochs=EPOCHS,
    class_weight=class_weight_dict,
    callbacks=callbacks
)

# simpan history untuk grafik di Streamlit
history_dict = {k: [float(v) for v in vals] for k, vals in history.history.items()}
with open(os.path.join(OUTPUT_DIR, "history.json"), "w") as f:
    json.dump(history_dict, f, indent=2)

# ------------------------------------------------------------------
# 8. EVALUASI DI TEST SET
# ------------------------------------------------------------------
test_gen.reset()
y_true = test_gen.classes
y_pred_prob = model.predict(test_gen).ravel()
y_pred = (y_pred_prob >= 0.5).astype(int)

idx_to_class = {v: k for k, v in train_gen.class_indices.items()}

cm = confusion_matrix(y_true, y_pred).tolist()
report = classification_report(
    y_true, y_pred, target_names=[idx_to_class[0], idx_to_class[1]], output_dict=True
)

# simpan detail prediksi per foto test (untuk ditampilkan contoh benar/salah di Streamlit)
sample_predictions = []
for fp, egg_id, true_idx, pred_idx, prob in zip(
    test_df["filepath"], test_df["egg_id"], y_true, y_pred, y_pred_prob
):
    sample_predictions.append({
        "filepath": fp,
        "egg_id": egg_id,
        "true_label": idx_to_class[true_idx],
        "pred_label": idx_to_class[pred_idx],
        "confidence": float(prob if pred_idx == 1 else 1 - prob),
        "correct": bool(true_idx == pred_idx)
    })

# Simpan detail split data (train, val, test)
split_details = []
for df_split, name in [(train_df, "Train"), (val_df, "Val"), (test_df, "Test")]:
    for _, row in df_split.iterrows():
        parent_dir = os.path.basename(os.path.dirname(row["filepath"]))
        split_details.append({
            "filepath": row["filepath"],
            "egg_id": f"{parent_dir.lower()}_{row['egg_id']}", # unik khusus untuk display di Streamlit
            "label": row["label"],
            "split": name
        })

eval_results = {
    "confusion_matrix": cm,
    "class_order": [idx_to_class[0], idx_to_class[1]],
    "classification_report": report,
    "test_accuracy": float((y_true == y_pred).mean()),
    "sample_predictions": sample_predictions,
    "split_details": split_details,
    "dataset_summary": {
        "total_foto": len(df),
        "total_telur_unik": int(df["egg_id"].nunique()),
        "utuh_foto": int((df["label"] == "Utuh").sum()),
        "utuh_telur_unik": int(df[df["label"] == "Utuh"]["egg_id"].nunique()),
        "retak_foto": int((df["label"] == "Retak").sum()),
        "retak_telur_unik": int(df[df["label"] == "Retak"]["egg_id"].nunique()),
        "train_foto": len(train_df),
        "train_telur_unik": int(train_df["egg_id"].nunique()),
        "val_foto": len(val_df),
        "val_telur_unik": int(val_df["egg_id"].nunique()),
        "test_foto": len(test_df),
        "test_telur_unik": int(test_df["egg_id"].nunique()),
        "split_method": "per-telur (group-based via GroupShuffleSplit, 70/15/15, seed=42)"
    }
}
with open(os.path.join(OUTPUT_DIR, "eval_results.json"), "w") as f:
    json.dump(eval_results, f, indent=2)

print(f"\nTest Accuracy: {eval_results['test_accuracy']*100:.2f}%")
print("Confusion Matrix:", cm)

# ------------------------------------------------------------------
# 9. SIMPAN MODEL FINAL + EXPORT TFLITE
# ------------------------------------------------------------------
model.save(os.path.join(MODEL_DIR, "egg_classifier.h5"))

converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()
with open(os.path.join(MODEL_DIR, "egg_classifier.tflite"), "wb") as f:
    f.write(tflite_model)

print("\nSelesai. Model & hasil evaluasi tersimpan di folder 'model/' dan 'outputs/'.")