#!/usr/bin/env python3
"""
Convert all-MiniLM-L6-v2 sentence-transformer to CoreML format.

Produces:
  - OpenRSS/Resources/ML/AllMiniLML6V2.mlpackage  (~22MB, float16)
  - OpenRSS/Resources/ML/vocab.txt                 (~220KB)

Tested with: torch==2.7.0, transformers==4.51.0, coremltools==9.0
"""

import shutil
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
from transformers import AutoModel, AutoTokenizer

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
MAX_SEQ_LEN = 128
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "OpenRSS" / "Resources" / "ML"


class MiniLMWithPooling(nn.Module):
    """Wraps the transformer + mean-pooling into a single exportable graph."""

    def __init__(self, transformer):
        super().__init__()
        self.transformer = transformer

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        outputs = self.transformer(input_ids=input_ids, attention_mask=attention_mask)
        token_embeddings = outputs.last_hidden_state  # (batch, seq, 384)

        # Mean pooling: average non-padding token embeddings
        mask_expanded = attention_mask.unsqueeze(-1).float()  # (batch, seq, 1)
        sum_embeddings = (token_embeddings * mask_expanded).sum(dim=1)
        sum_mask = mask_expanded.sum(dim=1).clamp(min=1e-9)
        sentence_embedding = sum_embeddings / sum_mask  # (batch, 384)

        # L2 normalize
        sentence_embedding = torch.nn.functional.normalize(sentence_embedding, p=2, dim=1)

        return sentence_embedding


def convert():
    print(f"Downloading {MODEL_NAME} ...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    transformer = AutoModel.from_pretrained(MODEL_NAME)
    transformer.eval()

    model = MiniLMWithPooling(transformer)
    model.eval()

    # Fixed-shape inputs for CoreML
    dummy_input_ids = torch.zeros(1, MAX_SEQ_LEN, dtype=torch.long)
    dummy_attention_mask = torch.ones(1, MAX_SEQ_LEN, dtype=torch.long)

    print("Exporting model with torch.export ...")
    exported = torch.export.export(
        model,
        (dummy_input_ids, dummy_attention_mask),
        strict=False,
    )
    exported = exported.run_decompositions({})

    print("Converting to CoreML ...")
    mlmodel = ct.convert(
        exported,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="embedding"),
        ],
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS16,
    )

    mlmodel.author = "sentence-transformers (MIT)"
    mlmodel.short_description = (
        "all-MiniLM-L6-v2 sentence embeddings (384-dim, float16). "
        "Input: WordPiece token IDs + attention mask. "
        "Output: L2-normalized sentence embedding."
    )

    # Save outputs
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    mlpackage_path = OUTPUT_DIR / "AllMiniLML6V2.mlpackage"
    if mlpackage_path.exists():
        shutil.rmtree(mlpackage_path)
    mlmodel.save(str(mlpackage_path))
    print(f"Saved {mlpackage_path}")

    # Export vocab.txt
    vocab = tokenizer.get_vocab()
    vocab_sorted = sorted(vocab.items(), key=lambda x: x[1])
    vocab_path = OUTPUT_DIR / "vocab.txt"
    with open(vocab_path, "w") as f:
        for token, _ in vocab_sorted:
            f.write(token + "\n")
    print(f"Saved {vocab_path} ({len(vocab_sorted)} tokens)")

    # Verify
    print("\nVerifying model ...")
    test_text = "Apple announces new iPhone features at WWDC"
    encoded = tokenizer(
        test_text, max_length=MAX_SEQ_LEN, padding="max_length",
        truncation=True, return_tensors="np"
    )
    pred = mlmodel.predict({
        "input_ids": encoded["input_ids"].astype(np.int32),
        "attention_mask": encoded["attention_mask"].astype(np.int32),
    })
    emb = pred["embedding"].flatten()
    print(f"Embedding shape: {emb.shape}")
    print(f"L2 norm: {np.linalg.norm(emb):.4f} (should be ~1.0)")
    print(f"First 5 values: {emb[:5]}")

    # Cross-check against PyTorch
    with torch.no_grad():
        pt_input_ids = torch.tensor(encoded["input_ids"], dtype=torch.long)
        pt_mask = torch.tensor(encoded["attention_mask"], dtype=torch.long)
        pt_emb = model(pt_input_ids, pt_mask).numpy().flatten()
    cosine_sim = np.dot(emb, pt_emb) / (np.linalg.norm(emb) * np.linalg.norm(pt_emb))
    print(f"CoreML vs PyTorch cosine similarity: {cosine_sim:.6f} (should be > 0.999)")

    if cosine_sim < 0.99:
        print("WARNING: Low similarity — check conversion!")
    else:
        print("\nConversion successful!")

    # Size report
    mlpackage_size = sum(f.stat().st_size for f in mlpackage_path.rglob("*") if f.is_file())
    print(f"\n.mlpackage size: {mlpackage_size / 1024 / 1024:.1f} MB")
    print(f"vocab.txt size: {vocab_path.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    convert()
