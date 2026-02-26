#!/usr/bin/env python3
"""
Resolve AWS Batch array child jobs to EC2 instances.

Default output is a fixed-width table (stable alignment in terminals).
Use --format tsv/csv for machine-readable output.
"""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import boto3
from botocore.exceptions import ClientError


def _chunks(seq: Sequence[str], n: int) -> Iterable[List[str]]:
    for i in range(0, len(seq), n):
        yield list(seq[i : i + n])


def _list_jobs_paginated(batch, *, array_job_id: str, status: str) -> List[dict]:
    out: List[dict] = []
    token: Optional[str] = None
    while True:
        kwargs = {"arrayJobId": array_job_id, "jobStatus": status}
        if token:
            kwargs["nextToken"] = token
        resp = batch.list_jobs(**kwargs)
        out.extend(resp.get("jobSummaryList", []))
        token = resp.get("nextToken")
        if not token:
            return out


def _parse_child_index(job_id: str) -> Optional[int]:
    if ":" not in job_id:
        return None
    try:
        return int(job_id.rsplit(":", 1)[1])
    except ValueError:
        return None


@dataclass(frozen=True)
class _ClusterInfo:
    compute_environment_arn: str
    compute_environment_name: str
    ecs_cluster_arn: str


def _get_queue_arn_from_job(batch, *, job_id: str) -> str:
    resp = batch.describe_jobs(jobs=[job_id])
    jobs = resp.get("jobs", [])
    if not jobs:
        raise RuntimeError(f"Job not found: {job_id}")
    q = jobs[0].get("jobQueue")
    if not q:
        raise RuntimeError(f"Job has no jobQueue field: {job_id}")
    return q


def _get_compute_envs_for_queue(batch, *, queue_arn_or_name: str) -> List[str]:
    resp = batch.describe_job_queues(jobQueues=[queue_arn_or_name])
    qs = resp.get("jobQueues", [])
    if not qs:
        raise RuntimeError(f"Job queue not found: {queue_arn_or_name}")
    order = qs[0].get("computeEnvironmentOrder", [])
    return [x["computeEnvironment"] for x in sorted(order, key=lambda d: d["order"])]


def _describe_compute_env_clusters(batch, *, compute_env_arns_or_names: List[str]) -> List[_ClusterInfo]:
    resp = batch.describe_compute_environments(computeEnvironments=compute_env_arns_or_names)
    ces = resp.get("computeEnvironments", [])
    if not ces:
        raise RuntimeError("No compute environments returned.")
    out: List[_ClusterInfo] = []
    for ce in ces:
        out.append(
            _ClusterInfo(
                compute_environment_arn=ce["computeEnvironmentArn"],
                compute_environment_name=ce["computeEnvironmentName"],
                ecs_cluster_arn=ce["ecsClusterArn"],
            )
        )
    return out


def _ecs_container_instance_to_ec2_instance_id(
    ecs,
    *,
    clusters: List[_ClusterInfo],
    container_instance_arn: str,
) -> Tuple[Optional[str], Optional[_ClusterInfo]]:
    for c in clusters:
        try:
            resp = ecs.describe_container_instances(
                cluster=c.ecs_cluster_arn,
                containerInstances=[container_instance_arn],
            )
            cis = resp.get("containerInstances", [])
            if cis:
                return cis[0].get("ec2InstanceId"), c
        except ClientError:
            continue
    return None, None


def _ec2_describe_instances(ec2, *, instance_ids: List[str]) -> Dict[str, dict]:
    if not instance_ids:
        return {}
    resp = ec2.describe_instances(InstanceIds=instance_ids)
    out: Dict[str, dict] = {}
    for r in resp.get("Reservations", []):
        for inst in r.get("Instances", []):
            out[inst["InstanceId"]] = inst
    return out


def _format_table(headers: List[str], rows: List[List[str]]) -> str:
    # Compute widths with a small right padding.
    widths = [len(h) for h in headers]
    for r in rows:
        for i, cell in enumerate(r):
            widths[i] = max(widths[i], len(cell))
    widths = [w + 2 for w in widths]

    def fmt_row(r: List[str]) -> str:
        return "".join((r[i] if r[i] else "").ljust(widths[i]) for i in range(len(headers))).rstrip()

    out_lines = [fmt_row(headers)]
    out_lines.extend(fmt_row(r) for r in rows)
    return "\n".join(out_lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", required=True)
    ap.add_argument("--array-job-id", required=True, help="Parent array job id (no :index suffix).")
    ap.add_argument(
        "--statuses",
        nargs="+",
        default=["RUNNING", "STARTING", "RUNNABLE", "SUCCEEDED", "FAILED"],
        help="Child job statuses to include.",
    )
    ap.add_argument("--format", choices=["table", "tsv", "csv"], default="table")
    args = ap.parse_args()

    batch = boto3.client("batch", region_name=args.region)
    ecs = boto3.client("ecs", region_name=args.region)
    ec2 = boto3.client("ec2", region_name=args.region)

    queue_arn = _get_queue_arn_from_job(batch, job_id=args.array_job_id)
    ce_arns = _get_compute_envs_for_queue(batch, queue_arn_or_name=queue_arn)
    clusters = _describe_compute_env_clusters(batch, compute_env_arns_or_names=ce_arns)

    summaries: List[dict] = []
    for st in args.statuses:
        summaries.extend(_list_jobs_paginated(batch, array_job_id=args.array_job_id, status=st))

    child_ids = [s["jobId"] for s in summaries]
    children: Dict[str, dict] = {}
    for ids in _chunks(child_ids, 100):
        resp = batch.describe_jobs(jobs=ids)
        for j in resp.get("jobs", []):
            children[j["jobId"]] = j

    job_to_ec2: Dict[str, Tuple[Optional[str], Optional[_ClusterInfo]]] = {}
    ec2_ids: List[str] = []
    for job_id, j in children.items():
        container_instance_arn = j.get("container", {}).get("containerInstanceArn")
        if not container_instance_arn:
            job_to_ec2[job_id] = (None, None)
            continue
        ec2_id, cluster_info = _ecs_container_instance_to_ec2_instance_id(
            ecs,
            clusters=clusters,
            container_instance_arn=container_instance_arn,
        )
        job_to_ec2[job_id] = (ec2_id, cluster_info)
        if ec2_id:
            ec2_ids.append(ec2_id)

    inst_map = _ec2_describe_instances(ec2, instance_ids=sorted(set(ec2_ids)))

    headers = [
        "child_index",
        "status",
        "job_id",
        "status_reason",
        "ec2_instance_id",
        "ec2_instance_type",
        "ec2_lifecycle",
        "availability_zone",
        "compute_environment",
    ]

    def _sort_key(s: dict) -> Tuple[int, int]:
        idx = _parse_child_index(s["jobId"])
        return (0 if idx is not None else 1, idx if idx is not None else 10**9)

    rows: List[List[str]] = []
    for s in sorted(summaries, key=_sort_key):
        job_id = s["jobId"]
        j = children.get(job_id, {})
        status_reason = j.get("statusReason") or ""

        ec2_id, cluster_info = job_to_ec2.get(job_id, (None, None))
        inst = inst_map.get(ec2_id, {}) if ec2_id else {}

        rows.append(
            [
                "" if _parse_child_index(job_id) is None else str(_parse_child_index(job_id)),
                s.get("status", "") or "",
                job_id,
                status_reason,
                ec2_id or "",
                inst.get("InstanceType", "") or "",
                inst.get("InstanceLifecycle", "") or "",
                (inst.get("Placement") or {}).get("AvailabilityZone", "") or "",
                (cluster_info.compute_environment_name if cluster_info else "") or "",
            ]
        )

    if args.format == "table":
        sys.stdout.write(_format_table(headers, rows) + "\n")
        return 0

    delimiter = "\t" if args.format == "tsv" else ","
    w = csv.writer(sys.stdout, delimiter=delimiter)
    w.writerow(headers)
    w.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

