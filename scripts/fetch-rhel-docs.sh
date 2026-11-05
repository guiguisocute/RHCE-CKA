#!/usr/bin/env bash
# 下载 RHCSA / RHCE 相关的 RHEL 官方 PDF 手册到 references/rhel/<版本>/
#
# 用法：
#   ./scripts/fetch-rhel-docs.sh          # 默认 RHEL 10
#   ./scripts/fetch-rhel-docs.sh 9        # 下载 RHEL 9 版本（如果你报考的是 RHEL 9 版考试）
#
# 文件名规则：docs.redhat.com/en/documentation/red_hat_enterprise_linux/<ver>/pdf/<slug>/Red_Hat_Enterprise_Linux-<ver>-<Title>-en-US.pdf
# 脚本先从 html-single 页面里找 PDF 链接，找不到再按规则拼文件名；失败的条目会在最后列出，不会中断。
set -u

VER="${1:-10}"
BASE="https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/${VER}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/references/rhel/${VER}"
mkdir -p "$OUT"

# slug|PDF 标题部分（大小写与官网一致；留空则按 slug 首字母大写自动拼）|对应考试
GUIDES=(
  "managing_software_with_the_dnf_tool|Managing_software_with_the_DNF_tool|RHCSA"
  "managing_storage_devices|Managing_storage_devices|RHCSA"
  "managing_file_systems|Managing_file_systems|RHCSA"
  "configuring_and_managing_logical_volumes|Configuring_and_managing_logical_volumes|RHCSA"
  "configuring_and_managing_networking|Configuring_and_managing_networking|RHCSA"
  "configuring_firewalls_and_packet_filters|Configuring_firewalls_and_packet_filters|RHCSA"
  "using_selinux|Using_SELinux|RHCSA"
  "managing_monitoring_and_updating_the_kernel|Managing_monitoring_and_updating_the_kernel|RHCSA"
  "configuring_and_using_network_file_services|Configuring_and_using_network_file_services|RHCSA"
  "configuring_basic_system_settings|Configuring_basic_system_settings|RHCSA"
  "managing_systemd|Managing_systemd|RHCSA"
  "security_hardening|Security_hardening|RHCSA"
  "interactive_installation|Interactive_installation|RHCSA"
  "automating_system_administration_by_using_rhel_system_roles|Automating_system_administration_by_using_RHEL_system_roles|RHCE"
  "building_running_and_managing_containers|Building_running_and_managing_containers|RHCSA(RHEL9)/CKA"
)

ok=(); fail=()
for entry in "${GUIDES[@]}"; do
  IFS='|' read -r slug title exam <<<"$entry"
  [ -n "$title" ] || title="$(tr '[:lower:]' '[:upper:]' <<<"${slug:0:1}")${slug:1}"

  # 1) 从 html-single 页面抓 PDF 链接（官网改名时更稳）
  url="$(curl -fsSL --max-time 30 "${BASE}/html-single/${slug}/index" 2>/dev/null \
        | grep -oE "/en/documentation/red_hat_enterprise_linux/${VER}/pdf/${slug}/[^\"']+\.pdf" | head -1)"
  [ -n "$url" ] && url="https://docs.redhat.com${url}"
  # 2) 兜底：按规则拼
  [ -n "$url" ] || url="${BASE}/pdf/${slug}/Red_Hat_Enterprise_Linux-${VER}-${title}-en-US.pdf"

  dest="${OUT}/$(basename "$url")"
  printf '%-62s ' "[$exam] $slug"
  if curl -fsSL --max-time 300 -o "${dest}.part" "$url" && head -c 4 "${dest}.part" | grep -q '%PDF'; then
    mv "${dest}.part" "$dest"; echo "OK  $(du -h "$dest" | cut -f1)"; ok+=("$slug")
  else
    rm -f "${dest}.part"; echo "失败"; fail+=("$slug  ->  ${BASE}/html-single/${slug}/index")
  fi
done

echo
echo "完成：${#ok[@]} 个成功，${#fail[@]} 个失败。文件位于 ${OUT}"
if [ "${#fail[@]}" -gt 0 ]; then
  echo "以下手册在 RHEL ${VER} 中可能已改名或拆分，请到 ${BASE} 手动查找："
  printf '  - %s\n' "${fail[@]}"
fi
