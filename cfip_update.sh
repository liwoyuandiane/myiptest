#!/bin/bash

# Cloudflare API 相关信息
CF_API_EMAIL="suolunxin@163.com"
CF_API_KEY="534103c6df130d9707a01d1a1a9bf1d92a28a"
CF_ZONE_ID="2c5201f362cc1ed44052a058e236ff9e"
DOMAIN_NAME="iptest-v4.ceshi0.eu.org"  # 需要添加 DNS 记录的域名

# 文件路径和其他常量
FILE_PATH="$1"  # 从命令行参数获取IP地址文件路径
TTL=1            # TTL 设置为 1 秒

# 检查是否安装了 jq 工具
if ! command -v jq &> /dev/null; then
    echo "错误: 未找到 'jq' 命令。请安装 'jq' (https://stedolan.github.io/jq/) 后再运行此脚本。"
    exit 1
fi

# 检查命令行参数
if [ $# -ne 1 ]; then
    echo "用法: $0 <realip-yxip.txt>"
    exit 1
fi

# 检查文件是否存在
if [ ! -f "$FILE_PATH" ]; then
    echo "错误: 文件 $FILE_PATH 不存在。"
    exit 1
fi

# 获取当前域名的所有 DNS 记录
get_dns_records() {
    local url="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${DOMAIN_NAME}"
    local response=$(curl -s -X GET "$url" \
                    -H "Content-Type: application/json" \
                    -H "X-Auth-Email: ${CF_API_EMAIL}" \
                    -H "X-Auth-Key: ${CF_API_KEY}")

    echo "$response"
}

# 删除所有的 DNS 记录
delete_all_dns_records() {
    local dns_records=$(get_dns_records)
    local record_count=$(echo "$dns_records" | jq '.result | length')

    for i in $(seq 0 $(($record_count - 1))); do
        local record_id=$(echo "$dns_records" | jq -r ".result[$i].id")
        delete_dns_record "$record_id"
    done
}

# 删除特定的 DNS 记录
delete_dns_record() {
    local record_id=$1
    local url="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}"
    local response=$(curl -s -X DELETE "$url" \
                    -H "Content-Type: application/json" \
                    -H "X-Auth-Email: ${CF_API_EMAIL}" \
                    -H "X-Auth-Key: ${CF_API_KEY}")

    # 检查删除成功与否
    local success=$(echo "$response" | jq -r '.success')
    if [ "$success" != "true" ]; then
        echo "删除 DNS 记录失败，记录 ID: ${record_id}。错误信息: $(echo "$response" | jq -r '.errors[0].message')"
        exit 1
    fi
}

# 添加 DNS 记录为新的 IP 地址
add_dns_record() {
    local ip_address=$1
    local url="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records"
    local data=$(cat <<EOF
{
  "type": "A",
  "name": "${DOMAIN_NAME}",
  "content": "${ip_address}",
  "ttl": ${TTL},
  "proxied": false
}
EOF
)

    # 发送请求并处理响应
    local response=$(curl -s -X POST "$url" \
                    -H "Content-Type: application/json" \
                    -H "X-Auth-Email: ${CF_API_EMAIL}" \
                    -H "X-Auth-Key: ${CF_API_KEY}" \
                    --data "${data}")

    # 检查响应中的成功字段
    local success=$(echo "$response" | jq -r '.success')

    if [ "$success" = "true" ]; then
        echo "成功添加 ${DOMAIN_NAME} 的 DNS 记录，IP 地址为 ${ip_address}"
    else
        echo "添加 DNS 记录失败。错误信息: $(echo "$response" | jq -r '.errors[0].message')"
        exit 1
    fi
}

# 主程序开始
# 获取当前域名的所有 DNS 记录
dns_records=$(get_dns_records)

# 解析当前域名的所有 IP 地址
current_ips=$(echo "$dns_records" | jq -r '.result[].content')

# 输出当前解析的 IP 地址
echo "当前域名 ${DOMAIN_NAME} 解析的 IP 地址为：$current_ips"

# 从文件中获取新的 IP 地址
new_ip=$(head -n 1 "$FILE_PATH" | awk '{print $1}')

# 检查新的 IP 地址是否与当前解析的 IP 相同
if echo "$current_ips" | grep -wq "$new_ip"; then
    echo "当前域名 ${DOMAIN_NAME} 上的 DNS 记录已经是 $new_ip，任务取消。"
else
    # 删除当前域名的所有 DNS 记录
    delete_all_dns_records
    
    # 添加新的 DNS 记录
    add_dns_record "$new_ip"
fi
