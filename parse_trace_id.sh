#!/bin/bash

###############################################################################
# OceanBase Trace ID 解析脚本
# 用法: ./parse_trace_id.sh YB42C0A82146-0006454899BBDC0D-0-0
# 作者：胖虎
# 基于源码分析：
# - deps/oblib/src/lib/profile/ob_trace_id.h (序列号生成)
# - src/observer/main.cpp (seq_generator_初始化)
# - deps/oblib/src/lib/time/ob_time_utility.cpp (current_time实现)
###############################################################################

if [ -z "$1" ]; then
    echo "=========================================="
    echo "  OceanBase Trace ID 解析脚本"
    echo "=========================================="
    echo ""
    echo "用法:sh $0 <trace_id>"
    echo "示例:sh $0 YB42C0A82146-0006454899BBDC0D-0-0"
    echo ""
    exit 1
fi

TRACE_ID="$1"

echo "=========================================="
echo "  OceanBase Trace ID 解析"
echo "=========================================="
echo "原始 Trace ID: $TRACE_ID"
echo ""

# 提取各部分
IP_TYPE=$(echo "$TRACE_ID" | cut -c1)
FIRST_PART=$(echo "$TRACE_ID" | cut -d'-' -f1 | cut -c2-)
SECOND_PART=$(echo "$TRACE_ID" | cut -d'-' -f2)
THIRD_PART=$(echo "$TRACE_ID" | cut -d'-' -f3)
FOURTH_PART=$(echo "$TRACE_ID" | cut -d'-' -f4)

FIRST_PART_UPPER=$(echo "$FIRST_PART" | tr '[:lower:]' '[:upper:]')
SEQ_HEX=$(echo "$SECOND_PART" | tr '[:lower:]' '[:upper:]')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "【IP 地址和端口】"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$IP_TYPE" == "Y" ]; then
    echo "IP 版本: IPv4"

    # 补全到12位（48位 = IP 32位 + 端口 16位）
    FIRST_FULL=$(printf "%012s" "$FIRST_PART_UPPER" | tr ' ' '0')

    # 提取IP（低32位，后8个字符）
    IP_HEX=$(echo "$FIRST_FULL" | cut -c5-12)

    # IP是大端序（源码：ob_net_util.cpp 中使用 ntohl）
    B1=$(echo "$IP_HEX" | cut -c1-2)
    B2=$(echo "$IP_HEX" | cut -c3-4)
    B3=$(echo "$IP_HEX" | cut -c5-6)
    B4=$(echo "$IP_HEX" | cut -c7-8)

    IP1=$((16#$B1))
    IP2=$((16#$B2))
    IP3=$((16#$B3))
    IP4=$((16#$B4))
    IP_ADDR="${IP1}.${IP2}.${IP3}.${IP4}"

    # 提取端口（位32-47，字符1-4）
    PORT_HEX=$(echo "$FIRST_FULL" | cut -c1-4)
    PORT=$((16#$PORT_HEX))

    echo "IP 地址: $IP_ADDR"
    echo "端口号: $PORT"
    echo ""
    echo "详细解析:"
    echo "  • 原始十六进制: $FIRST_PART_UPPER"
    echo "  • 端口部分（高16位）: $PORT_HEX → $PORT"
    echo "  • IP 部分（低32位）: $IP_HEX → $IP_ADDR"

else
    echo "IP 版本: IPv6"
    echo "IPv6 解析暂未实现"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "【序列号信息】"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SEQ_DEC=$(printf "%lu" "0x$SEQ_HEX" 2>/dev/null || echo "$SEQ_HEX")

echo "序列号（十六进制）: $SEQ_HEX"
echo "序列号（十进制）: $SEQ_DEC"
echo ""

# 序列号结构分析（基于源码 ob_trace_id.h gen_seq() 函数）
echo "序列号组成分析:"
echo "  序列号 = 启动时间戳（微秒） + 线程空间偏移 + 请求计数"
echo ""

# 将序列号作为微秒时间戳解析
SEQ_TS_SEC=$((SEQ_DEC / 1000000))
SEQ_TS_USEC_IN_SEC=$((SEQ_DEC % 1000000))

echo "作为时间戳解析:"
echo "  • 秒部分: $SEQ_TS_SEC"
echo "  • 微秒部分: $SEQ_TS_USEC_IN_SEC"

# 转换为日期时间
if command -v date >/dev/null 2>&1; then
    SEQ_TIME=$(date -d "@$SEQ_TS_SEC" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$SEQ_TS_SEC" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    if [ -n "$SEQ_TIME" ]; then
        echo "  • 对应时间: $SEQ_TIME"
        echo "    注: 这是序列号对应的时间，受请求计数影响"
    fi
fi

echo ""

# BATCH 机制分析（源码：enum { BATCH = 1<<20 }）
BATCH=1048576
BATCH_HEX="100000"

echo "线程空间分析:"
echo "  • BATCH 大小: $BATCH (0x$BATCH_HEX)"
echo "  • 说明: 每个线程分配 1,048,576 个序列号"
echo ""

# 提取高位和低位
HIGH_BITS_DEC=$((SEQ_DEC / BATCH))
LOW_BITS_DEC=$((SEQ_DEC % BATCH))
HIGH_BITS_HEX=$(printf "0x%X" "$HIGH_BITS_DEC")
LOW_BITS_HEX=$(printf "0x%X" "$LOW_BITS_DEC")

echo "位段划分:"
echo "  • 高44位（除以BATCH）: $HIGH_BITS_DEC ($HIGH_BITS_HEX)"
echo "    包含: 启动时间戳的主要部分（秒级时间戳在线程空间内不变）"
echo "  • 低20位（模BATCH）: $LOW_BITS_DEC ($LOW_BITS_HEX)"
echo "    包含: 启动时间戳微秒部分的低20位 + 线程内请求计数"
echo ""

# 从高位估算时间戳
HIGH_TS_SEC=$((HIGH_BITS_DEC / 1000))  # 高位/1000 接近秒数
HIGH_TS_USEC=$((HIGH_BITS_DEC % 1000 * 1000 + LOW_BITS_DEC))

echo "时间戳估算:"
echo "  • 高44位包含的时间戳（微秒/1000）: $HIGH_BITS_DEC"
echo "  • 对应秒数（估算）: $HIGH_TS_SEC"

if command -v date >/dev/null 2>&1; then
    HIGH_TIME=$(date -d "@$HIGH_TS_SEC" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$HIGH_TS_SEC" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    if [ -n "$HIGH_TIME" ]; then
        echo "  • 对应时间: $HIGH_TIME（估算）"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "【扩展信息】"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

INNER_SQL_DEC=$((16#$THIRD_PART))
SUB_TASK_DEC=$((16#$FOURTH_PART))

echo "Inner SQL ID: $INNER_SQL_DEC"
echo "Sub Task ID: $SUB_TASK_DEC"

if [ $INNER_SQL_DEC -gt 0 ]; then
    echo "  • 执行 ID (Execution ID): $((INNER_SQL_DEC + 1))"
    echo "  • 说明: 嵌套 SQL 执行"
else
    echo "  • 说明: 非嵌套 SQL 执行"
fi

if [ $SUB_TASK_DEC -gt 0 ]; then
    echo "  • 说明: 并行任务"
else
    echo "  • 说明: 非并行任务"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "【完整解析总结】"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Trace ID: $TRACE_ID"
echo ""
echo "来源服务器: $IP_ADDR:$PORT"
if [ -n "$HIGH_TIME" ]; then
    echo "服务器启动时刻（估算）: $HIGH_TIME"
fi
echo "SQL 类型: $([ $INNER_SQL_DEC -gt 0 ] && echo '嵌套SQL' || echo '普通SQL')"
echo "任务类型: $([ $SUB_TASK_DEC -gt 0 ] && echo '并行任务' || echo '单线程任务')"
echo ""
echo "说明:"
echo "  1. 序列号包含服务器启动时间戳，但会被请求计数修改"
echo "  2. 高44位保留了启动时间的主要信息（秒级精度）"
echo "  3. 低20位混合了微秒时间戳和请求计数，无法准确分离"
echo "  4. 因此无法从单个trace_id准确获取启动时间和请求计数"
echo ""
echo "=========================================="
