#!/usr/bin/env bash
# 从官方 GitHub 仓库重新拉取 references/ 下的文档（CKA 考纲、Kubernetes/Helm/Gateway API、Ansible 文档等）
# 用法：./scripts/update-references.sh
# 依赖：git、curl。只做稀疏浅克隆，几十 MB 流量。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="${ROOT}/references"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sparse_clone() { # repo dir paths...
  local repo="$1" dir="$2"; shift 2
  git clone -q --depth 1 --filter=blob:none --sparse "https://github.com/${repo}.git" "${TMP}/${dir}"
  git -C "${TMP}/${dir}" sparse-checkout set "$@"
  echo "  ${repo} @ $(git -C "${TMP}/${dir}" log -1 --format='%h %cs')"
}

echo "==> 拉取官方仓库"
git clone -q --depth 1 https://github.com/cncf/curriculum.git "${TMP}/curriculum"
echo "  cncf/curriculum @ $(git -C "${TMP}/curriculum" log -1 --format='%h %cs')"
sparse_clone kubernetes/website k8s content/en/docs content/en/examples
sparse_clone helm/helm-www helm docs
sparse_clone kubernetes-sigs/gateway-api gw site/content/en
sparse_clone ansible/ansible-documentation ansible docs/docsite/rst
sparse_clone ansible/ansible-navigator nav docs

echo "==> CKA 考纲"
rm -f "${R}"/cka/CKA_Curriculum_*.pdf
cp "${TMP}"/curriculum/CKA_Curriculum_*.pdf "${R}/cka/"
cp "${TMP}/curriculum/cka/README.md" "${R}/cka/CNCF-CKA-curriculum-README.md"
ls "${R}"/cka/CKA_Curriculum_*.pdf

echo "==> Kubernetes 文档"
K="${R}/cka/kubernetes-docs"; rm -rf "$K"; mkdir -p "$K"
for d in concepts tasks setup tutorials reference images; do cp -r "${TMP}/k8s/content/en/docs/$d" "$K/"; done
cp "${TMP}/k8s/content/en/docs/_index.md" "$K/"
rm -rf "$K/reference/kubernetes-api"   # 自动生成的 API 字段参考，考试时用 kubectl explain 更快
cp -r "${TMP}/k8s/content/en/examples" "$K/examples"
cp "${TMP}/k8s/LICENSE" "$K/LICENSE"

echo "==> Helm 文档"
H="${R}/cka/helm-docs"; rm -rf "$H"; mkdir -p "$H"
cp -r "${TMP}/helm/docs/." "$H/"; cp "${TMP}/helm/LICENSE" "$H/LICENSE"

echo "==> Gateway API 文档"
G="${R}/cka/gateway-api-docs"; rm -rf "$G"; mkdir -p "$G"
for d in docs guides reference; do cp -r "${TMP}/gw/site/content/en/$d" "$G/"; done
cp "${TMP}/gw/LICENSE" "$G/LICENSE"

echo "==> Ansible 文档"
A="${R}/rhce/ansible-docs"; rm -rf "$A"; mkdir -p "$A"
for d in getting_started getting_started_ee installation_guide inventory_guide command_guide playbook_guide \
         vault_guide collections_guide galaxy module_plugin_guide tips_tricks reference_appendices images shared_snippets; do
  cp -r "${TMP}/ansible/docs/docsite/rst/$d" "$A/"
done
cp "${TMP}/ansible/COPYING" "$A/COPYING"

echo "==> ansible-navigator 文档"
N="${R}/rhce/ansible-navigator-docs"; rm -rf "$N"; mkdir -p "$N"
cp -r "${TMP}/nav/docs/." "$N/"; cp "${TMP}/nav/LICENSE" "$N/LICENSE"

echo "==> RHEL System Roles 上游 README"
S="${R}/rhce/rhel-system-roles-upstream"; mkdir -p "$S"
for role in firewall selinux storage timesync network crypto_policies; do
  curl -fsSL -o "$S/${role}-README.md" "https://raw.githubusercontent.com/linux-system-roles/${role}/main/README.md"
done
curl -fsSL -o "$S/LICENSE" "https://raw.githubusercontent.com/linux-system-roles/timesync/main/COPYING"  # MIT

find "$R" -name OWNERS -delete
find "$R" -xtype l -delete   # 上游仓库里指向稀疏克隆之外的软链接
echo "==> 完成。记得更新 references/README.md 里的版本/commit 表，并用 git diff --stat 检查变化。"
