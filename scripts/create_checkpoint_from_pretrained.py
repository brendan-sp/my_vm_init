#!/usr/bin/env python3
"""
Create a resumable checkpoint from a pretrained model file.
This initializes optimizer, scheduler, scaler, and reporter states
so that --resume true can be used in future training sessions.

Usage:
    python create_checkpoint_from_pretrained.py \
        --pretrained /path/to/pretrained_model.pth \
        --config /path/to/config.yaml \
        --output /path/to/exp_dir/checkpoint.pth \
        --spk_num 156279
"""

import argparse
import torch
import yaml
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Create a resumable checkpoint from pretrained weights"
    )
    parser.add_argument(
        "--pretrained", required=True, help="Path to pretrained model weights"
    )
    parser.add_argument(
        "--config", required=True, help="Path to training config.yaml"
    )
    parser.add_argument(
        "--output", required=True, help="Output path for checkpoint.pth"
    )
    parser.add_argument(
        "--spk_num", type=int, required=True, help="Number of speakers in new dataset"
    )
    parser.add_argument(
        "--ignore_init_mismatch", action="store_true", default=True,
        help="Ignore mismatched layers (e.g., classifier head)"
    )
    args = parser.parse_args()

    print(f"Loading config from {args.config}")
    with open(args.config, "r") as f:
        config = yaml.safe_load(f)

    # Import ESPnet modules
    from espnet2.tasks.spk import SpeakerTask
    from espnet2.train.reporter import Reporter
    from torch.cuda.amp import GradScaler

    # Build model
    print(f"Building model with {args.spk_num} speakers...")
    
    # Create a minimal args namespace for model building
    model_args = argparse.Namespace(
        # Frontend
        frontend=config.get("frontend", "asteroid_frontend"),
        frontend_conf=config.get("frontend_conf", {}),
        # Specaug (optional)
        specaug=config.get("specaug", None),
        specaug_conf=config.get("specaug_conf", {}),
        # Normalize (optional)
        normalize=config.get("normalize", None),
        normalize_conf=config.get("normalize_conf", {}),
        # Input size (used when no frontend)
        input_size=config.get("input_size", None),
        # Encoder
        encoder=config.get("encoder", "rawnet3"),
        encoder_conf=config.get("encoder_conf", {}),
        # Pooling
        pooling=config.get("pooling", "chn_attn_stat"),
        pooling_conf=config.get("pooling_conf", {}),
        # Projector
        projector=config.get("projector", "rawnet3"),
        projector_conf=config.get("projector_conf", {}),
        # Loss
        loss=config.get("loss", "aamsoftmax_sc_topk"),
        loss_conf=config.get("loss_conf", {}),
        # Model
        model_conf=config.get("model_conf", {}),
        # Required args
        spk_num=args.spk_num,
        init=None,
    )
    
    model = SpeakerTask.build_model(model_args)
    print(f"Model built: {sum(p.numel() for p in model.parameters())/1e6:.2f}M parameters")

    # Load pretrained weights
    print(f"Loading pretrained weights from {args.pretrained}")
    pretrained_state = torch.load(args.pretrained, map_location="cpu")
    
    # Handle checkpoint vs model-only format
    if "model" in pretrained_state:
        pretrained_state = pretrained_state["model"]
    
    # Load with mismatch handling
    model_state = model.state_dict()
    loaded_keys = []
    skipped_keys = []
    
    for key, value in pretrained_state.items():
        if key in model_state:
            if model_state[key].shape == value.shape:
                model_state[key] = value
                loaded_keys.append(key)
            else:
                skipped_keys.append(f"{key}: {value.shape} -> {model_state[key].shape}")
        else:
            skipped_keys.append(f"{key}: not in model")
    
    model.load_state_dict(model_state)
    print(f"Loaded {len(loaded_keys)} parameters")
    if skipped_keys:
        print(f"Skipped {len(skipped_keys)} mismatched parameters:")
        for k in skipped_keys[:10]:  # Show first 10
            print(f"  - {k}")
        if len(skipped_keys) > 10:
            print(f"  ... and {len(skipped_keys) - 10} more")

    # Build optimizer
    print("Initializing optimizer...")
    optim_name = config.get("optim", "adam").lower()
    optim_conf = config.get("optim_conf", {"lr": 0.001})
    
    if optim_name == "adamw":
        optimizer = torch.optim.AdamW(model.parameters(), **optim_conf)
    elif optim_name == "adam":
        optimizer = torch.optim.Adam(model.parameters(), **optim_conf)
    elif optim_name == "sgd":
        optimizer = torch.optim.SGD(model.parameters(), **optim_conf)
    else:
        print(f"Warning: Unknown optimizer {optim_name}, defaulting to Adam")
        optimizer = torch.optim.Adam(model.parameters(), **optim_conf)
    
    print(f"  Using {optim_name} optimizer")

    # Build scheduler
    print("Initializing scheduler...")
    scheduler_conf = config.get("scheduler_conf", {})
    scheduler_name = config.get("scheduler", "CosineAnnealingWarmupRestarts")
    
    if scheduler_name == "CosineAnnealingWarmupRestarts":
        from espnet2.schedulers.cosine_anneal_warmup_restart import CosineAnnealingWarmupRestarts
        scheduler = CosineAnnealingWarmupRestarts(optimizer, **scheduler_conf)
    else:
        # Fallback to no scheduler state
        scheduler = None
        print(f"Warning: Scheduler {scheduler_name} not handled, saving without scheduler state")

    # Build scaler for AMP
    scaler = GradScaler()

    # Build reporter
    reporter = Reporter()

    # Create checkpoint dict
    checkpoint = {
        "model": model.state_dict(),
        "reporter": reporter.state_dict(),
        "optimizers": [optimizer.state_dict()],
        "schedulers": [scheduler.state_dict()] if scheduler else [{}],
        "scaler": scaler.state_dict(),
    }

    # Save checkpoint
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    torch.save(checkpoint, output_path)
    print(f"\nCheckpoint saved to {output_path}")
    print(f"You can now use: --resume true")
    print(f"Training will start from epoch 1 with fresh optimizer state.")


if __name__ == "__main__":
    main()
