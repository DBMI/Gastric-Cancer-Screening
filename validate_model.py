"""Validate an exported federated XGBoost model on external data.

Supports model artifacts exported by `server.py`, including raw bytes checkpoints
(e.g., `federated_model_best_global_roc_auc.bin`) and standard XGBoost model files.

Example:
   python validate_external_xgb.py \
      --model-path federated_models/federated_model_best_global_roc_auc.bin \
      --data-path  H:/Gastroentrology/"Gastric Cancer fedsync"/Tables/cchs_cohort_v2.csv \
      --target-column Cohort
"""

from __future__ import annotations

import argparse
import hashlib
import os

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import average_precision_score, log_loss, roc_auc_score


def _coerce_binary_target(target_series: pd.Series) -> np.ndarray:
    """Convert common binary labels to {0,1}, else factorize labels."""
    lowered = target_series.astype(str).str.strip().str.lower()
    mapping = {
        "0": 0,
        "1": 1,
        "false": 0,
        "true": 1,
        "no": 0,
        "yes": 1,
        "control": 0,
        "case": 1,
        "female": 0,
        "male": 1,
        "f": 0,
        "m": 1,
    }

    mapped = lowered.map(mapping)
    if mapped.notna().all():
        return mapped.astype(int).values

    numeric = pd.to_numeric(target_series, errors="coerce")
    if numeric.notna().all():
        unique_vals = np.sort(numeric.unique())
        if np.array_equal(unique_vals, np.array([0, 1])):
            return numeric.astype(int).values

    encoded, _ = pd.factorize(target_series, sort=True)
    return encoded.astype(int)


def _prepare_features(frame: pd.DataFrame) -> pd.DataFrame:
    """Convert mixed feature types to numeric matrix for XGBoost."""
    converted = frame.copy()

    def _stable_encode_token(value: str) -> float:
        digest = hashlib.md5(value.encode("utf-8")).hexdigest()[:8]
        return float(int(digest, 16))

    for column in converted.columns:
        series = converted[column]
        if pd.api.types.is_numeric_dtype(series):
            continue

        text = series.astype(str).str.strip().str.lower()
        text = text.replace({"": np.nan, "NA": np.nan, "N/A": np.nan, "None": np.nan, "nan": np.nan})
        as_numeric = pd.to_numeric(text, errors="coerce")
        if as_numeric.notna().mean() >= 0.95:
            converted[column] = as_numeric
        else:
            mapped = text.map(lambda item: np.nan if pd.isna(item) else _stable_encode_token(item))
            converted[column] = mapped

    return converted.astype(np.float32)


def load_external_data(
        data_path: str,
        target_column: str,
        drop_columns: list[str],
) -> tuple[pd.DataFrame, np.ndarray]:
    """Load full external dataset and apply same preprocessing as client."""
    df = pd.read_csv(data_path)

    if target_column not in df.columns:
        raise ValueError(
            f"Target column '{target_column}' not found. Available columns: {list(df.columns)}"
        )

    safe_drop = [column for column in drop_columns if column in df.columns and column != target_column]
    if safe_drop:
        df = df.drop(columns=safe_drop)

    y = _coerce_binary_target(df[target_column])
    X_df = df.drop(columns=[target_column])
    X_df = _prepare_features(X_df)
    return X_df, y


def load_booster(model_path: str) -> xgb.Booster:
    """Load booster from either standard file or raw bytes artifact."""
    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model file not found: {model_path}")

    booster = xgb.Booster()
    try:
        booster.load_model(model_path)
        return booster
    except xgb.core.XGBoostError:
        pass

    with open(model_path, "rb") as handle:
        model_bytes = handle.read()
    booster.load_model(bytearray(model_bytes))
    return booster


def evaluate_binary(y_true: np.ndarray, pos: np.ndarray, decision_threshold: float) -> dict:
    """Evaluate binary metrics."""
    pos = np.clip(pos, 1e-8, 1.0 - 1e-8)
    y_pred_proba = np.column_stack([1.0 - pos, pos])
    y_pred_label = (pos >= decision_threshold).astype(int)

    metrics = {
        "loss": float(log_loss(y_true, y_pred_proba, labels=[0, 1])),
        "roc_auc": 0.0,
        "pr_auc": 0.0,
        "pred_pos_rate": float(np.mean(y_pred_label)),
    }
    try:
        metrics["roc_auc"] = float(roc_auc_score(y_true, pos))
    except Exception:
        metrics["roc_auc"] = 0.0
    try:
        metrics["pr_auc"] = float(average_precision_score(y_true, pos))
    except Exception:
        metrics["pr_auc"] = 0.0
    return metrics


def build_prediction_table(
        index: pd.Index,
        y_true: np.ndarray,
        pos: np.ndarray,
        decision_threshold: float,
) -> pd.DataFrame:
    """Build per-row table of index, true label, class probabilities, prediction."""
    pos = np.clip(pos, 1e-8, 1.0 - 1e-8)
    table = pd.DataFrame(
        {
            "true_label": y_true.astype(int),
            "prob_class0": (1.0 - pos).astype(float),
            "prob_class1": pos.astype(float),
            "pred_label": (pos >= decision_threshold).astype(int),
        },
        index=index,
    )
    table.index.name = "index"
    return table


def _default_csv_path(model_path: str, data_path: str) -> str:
    """Build a default predictions .csv path from the model and data names."""
    model_stem = os.path.splitext(os.path.basename(model_path))[0]
    data_stem = os.path.splitext(os.path.basename(data_path))[0]
    return f"predictions_{model_stem}_on_{data_stem}.csv"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate exported federated XGBoost model on external data.")
    parser.add_argument("--model-path", required=True, help="Path to exported model file.")
    parser.add_argument("--data-path", required=True, help="Path to external CSV.")
    parser.add_argument("--target-column", default="Cohort", help="Target column in CSV.")
    parser.add_argument(
        "--drop-columns",
        default="",
        help="Comma-separated columns to drop before evaluation.",
    )
    parser.add_argument(
        "--decision-threshold",
        type=float,
        default=0.5,
        help="Threshold for `pred_pos_rate` reporting.",
    )
    parser.add_argument(
        "--output-csv",
        default="",
        help=(
            "Path to save the predictions table as .csv "
            "(index, true_label, prob_class0, prob_class1, pred_label). "
            "Defaults to predictions_<model>_on_<data>.csv."
        ),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    drop_columns = [entry.strip() for entry in args.drop_columns.split(",") if entry.strip()]
    decision_threshold = float(np.clip(args.decision_threshold, 0.01, 0.99))

    booster = load_booster(args.model_path)
    X_ext_df, y_ext = load_external_data(args.data_path, args.target_column, drop_columns)

    model_feature_names = booster.feature_names
    if model_feature_names:
        missing = [name for name in model_feature_names if name not in X_ext_df.columns]
        if missing:
            raise ValueError(
                "External data is missing model features: "
                + ", ".join(missing[:10])
                + (" ..." if len(missing) > 10 else "")
            )
        X_eval_df = X_ext_df.loc[:, model_feature_names]
    else:
        X_eval_df = X_ext_df

    model_features = int(booster.num_features())
    data_features = int(X_eval_df.shape[1])
    if model_features != data_features:
        raise ValueError(
            "Feature mismatch between model and external data: "
            f"model expects {model_features}, external data has {data_features}."
        )

    dtest = xgb.DMatrix(
        X_eval_df.values,
        label=y_ext,
        missing=np.nan,
        feature_names=[str(column) for column in X_eval_df.columns],
    )
    pred = booster.predict(dtest)

    print("[EXTERNAL] Validation configuration")
    print(f"  model: {args.model_path}")
    print(f"  data: {args.data_path}")
    print(f"  target: {args.target_column}")
    print(f"  samples: {len(y_ext)}")
    print(f"  features: {data_features}")

    if pred.ndim == 1:
        metrics = evaluate_binary(y_ext, pred, decision_threshold)
        print("\n[EXTERNAL] Metrics")
        print(f"  loss:         {metrics['loss']:.6f}")
        print(f"  roc_auc:      {metrics['roc_auc']:.4f}")
        print(f"  pr_auc:       {metrics['pr_auc']:.4f}")
        print(f"  pred_pos_rate:{metrics['pred_pos_rate']:.4f}")

        pred_table = build_prediction_table(
            X_eval_df.index, y_ext, pred, decision_threshold
        )
        csv_path = args.output_csv or _default_csv_path(args.model_path, args.data_path)
        pred_table.to_csv(csv_path, index=True)
        print(f"\n[EXTERNAL] Saved predictions table: {csv_path}")
    else:
        pred_labels = np.argmax(pred, axis=1)
        labels = list(np.unique(y_ext))
        loss = float(log_loss(y_ext, pred, labels=labels))
        print("\n[EXTERNAL] Multiclass metrics")
        print(f"  loss:         {loss:.6f}")
        print("  roc_auc:      (not reported here for multiclass)")
        print("  pr_auc:       (not reported here for multiclass)")

        proba_columns = {f"prob_class{i}": pred[:, i].astype(float) for i in range(pred.shape[1])}
        multi_table = pd.DataFrame(
            {"true_label": y_ext.astype(int), **proba_columns, "pred_label": pred_labels.astype(int)},
            index=X_eval_df.index,
        )
        multi_table.index.name = "index"
        csv_path = args.output_csv or _default_csv_path(args.model_path, args.data_path)
        multi_table.to_csv(csv_path, index=True)
        print(f"\n[EXTERNAL] Saved predictions table: {csv_path}")


if __name__ == "__main__":
    main()
