#!/bin/bash

# OceanBase故障节点管理脚本
# 功能：清理或重建故障节点租户副本

set -e

# 全局变量
TEST_MODE=false
VERBOSE_LOG=false
DB_CONNECTION_STRING=""
DB_HOST=""
DB_PORT=""
DB_USER=""
DB_PASS=""
DB_NAME="oceanbase"
FAULT_IP=""
OPERATION=""
LOG_FILE="ob_recovery_$(date +%Y%m%d_%H%M%S).log"
SQL_OUTPUT_FILE="generated_sql_$(date +%Y%m%d_%H%M%S).txt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "[$timestamp] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}INFO:${NC} $1"
}

log_success() {
    log "SUCCESS" "${GREEN}SUCCESS:${NC} $1"
}

log_warning() {
    log "WARNING" "${YELLOW}WARNING:${NC} $1"
}

log_error() {
    log "ERROR" "${RED}ERROR:${NC} $1"
}

log_verbose() {
    if [ "$VERBOSE_LOG" = true ]; then
        log "VERBOSE" "${CYAN}VERBOSE:${NC} $1"
    fi
}

# 显示用法
usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -t    测试模式：生成SQL但不执行，输出到文件
    -l    详细日志模式：打印更详细的日志信息
    -h    显示此帮助信息

示例:
    $0 -t          # 测试模式
    $0 -l          # 详细日志模式  
    $0 -t -l       # 测试模式+详细日志
EOF
}

# 解析命令行参数
parse_arguments() {
    while getopts "tlh" opt; do
        case $opt in
            t)
                TEST_MODE=true
                log_info "启用测试模式"
                ;;
            l)
                VERBOSE_LOG=true
                log_info "启用详细日志模式"
                ;;
            h)
                usage
                exit 0
                ;;
            \?)
                log_error "无效选项: -$OPTARG"
                usage
                exit 1
                ;;
        esac
    done
}

# 输入验证函数
validate_input() {
    local input=$1
    local type=$2
    
    case $type in
        ip)
            if [[ ! $input =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                log_error "IP地址格式不正确: $input"
                return 1
            fi
            ;;
        number)
            if [[ ! $input =~ ^[12]$ ]]; then
                log_error "请输入1或2"
                return 1
            fi
            ;;
        connection)
            if [[ ! $input =~ ^(cbclient|mysql) ]]; then
                log_error "连接串必须以cbclient或mysql开头"
                return 1
            fi
            ;;
    esac
    return 0
}

# 解析数据库连接串
parse_connection_string() {
    local conn_str="$1"
    
    log_verbose "解析连接串: $conn_str"
    
    # 移除可能的多余空格
    conn_str=$(echo "$conn_str" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 提取连接信息
    if [[ $conn_str =~ ^cbclient ]]; then
        # cbclient格式解析
        DB_HOST=$(echo "$conn_str" | grep -oP '(?<=-h)[^ ]+' | head -1)
        DB_PORT=$(echo "$conn_str" | grep -oP '(?<=-P)[^ ]+' | head -1)
        DB_USER=$(echo "$conn_str" | grep -oP '(?<=-u)[^ ]+' | head -1)
        DB_PASS=$(echo "$conn_str" | grep -oP '(?<=-p)[^ ]+' | head -1)
        DB_NAME=$(echo "$conn_str" | grep -oP '(?<=-D)[^ ]+' | head -1)
    elif [[ $conn_str =~ ^mysql ]]; then
        # mysql格式解析
        DB_HOST=$(echo "$conn_str" | grep -oP '(?<=-h)[^ ]+' | head -1)
        DB_PORT=$(echo "$conn_str" | grep -oP '(?<=-P)[^ ]+' | head -1)
        DB_USER=$(echo "$conn_str" | grep -oP '(?<=-u)[^ ]+' | head -1)
        DB_PASS=$(echo "$conn_str" | grep -oP '(?<=-p)[^ ]+' | head -1)
        DB_NAME=$(echo "$conn_str" | grep -oP '(?<=-D)[^ ]+' | head -1)
    fi
    
    # 设置默认值
    DB_PORT=${DB_PORT:-2881}
    DB_NAME=${DB_NAME:-oceanbase}
    
    log_verbose "解析结果: 主机=$DB_HOST, 端口=$DB_PORT, 用户=$DB_USER, 数据库=$DB_NAME"
}

# 获取数据库连接信息
get_db_connection() {
    log_info "请输入OceanBase数据库连接串"
    log_info "支持格式:"
    log_info "  - cbclient -h主机 -P端口 -u用户 -p密码 -D数据库"
    log_info "  - mysql -h主机 -P端口 -u用户 -p密码 -D数据库"
    
    while true; do
        read -p "连接串: " DB_CONNECTION_STRING
        
        if validate_input "$DB_CONNECTION_STRING" "connection"; then
            parse_connection_string "$DB_CONNECTION_STRING"
            
            if validate_db_connection; then
                log_success "数据库连接成功"
                break
            else
                log_error "数据库连接失败，请重新输入"
            fi
        fi
    done
}

# 验证数据库连接
validate_db_connection() {
    log_verbose "验证数据库连接..."
    
    # 使用解析后的连接信息进行测试
    local result
    result=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -e "SELECT 1;" 2>/dev/null | tail -1)
    
    if [ "$result" = "1" ]; then
        return 0
    else
        return 1
    fi
}

# 获取故障节点IP
get_fault_ip() {
    while true; do
        read -p "请输入故障节点observer的IP: " FAULT_IP
        if validate_input "$FAULT_IP" "ip"; then
            log_info "故障节点IP: $FAULT_IP"
            break
        fi
    done
}

# 选择操作
select_operation() {
    cat << EOF

请选择要执行的操作:
1. 清理故障节点租户副本
2. 重建故障节点租户副本

EOF
    
    while true; do
        read -p "请输入选择(1或2): " OPERATION
        if validate_input "$OPERATION" "number"; then
            case $OPERATION in
                1)
                    log_info "选择操作: 清理故障节点租户副本"
                    ;;
                2)
                    log_info "选择操作: 重建故障节点租户副本"
                    ;;
            esac
            break
        fi
    done
}

# 执行SQL函数
execute_sql() {
    local sql="$1"
    local step_desc="$2"
    local should_execute=true
    
    log_info "执行步骤: $step_desc"
    log_verbose "生成的SQL: $sql"
    
    if [ "$TEST_MODE" = true ]; then
        log_info "测试模式: SQL已保存到文件，不实际执行"
        echo "-- $step_desc" >> "$SQL_OUTPUT_FILE"
        echo "$sql;" >> "$SQL_OUTPUT_FILE"
        echo "" >> "$SQL_OUTPUT_FILE"
        should_execute=false
    fi
    
    if [ "$should_execute" = true ]; then
        local start_time=$(date +%s)
        
        log_verbose "开始执行SQL..."
        # 执行SQL并处理结果
        mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -e "$sql" 2>&1 | tee -a "$LOG_FILE"
        
        local exit_code=${PIPESTATUS[0]}
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        if [ $exit_code -eq 0 ]; then
            log_success "步骤完成 - 耗时: ${duration}秒"
        else
            log_error "步骤执行失败 - 耗时: ${duration}秒"
            return 1
        fi
    fi
    
    return 0
}

# 执行多行SQL结果
execute_sql_results() {
    local base_sql="$1"
    local step_desc="$2"
    
    log_info "执行步骤: $step_desc"
    log_verbose "基础SQL: $base_sql"
    
    # 替换故障IP
    local final_sql="${base_sql//192.192.33.77/$FAULT_IP}"
    
    # 执行基础SQL获取要执行的SQL语句
    local generated_sql
    generated_sql=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -N -e "$final_sql" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "基础SQL执行失败"
        return 1
    fi
    
    if [ -z "$generated_sql" ]; then
        log_warning "未生成SQL语句"
        return 0
    fi
    
    log_verbose "生成SQL数量: $(echo "$generated_sql" | wc -l)"
    
    # 将结果按行分割并执行
    while IFS= read -r sql_line; do
        if [ -n "$sql_line" ]; then
            execute_sql "$sql_line" "执行生成SQL" || return 1
        fi
    done <<< "$generated_sql"
    
    return 0
}

# 监控任务进度 - 优化时间过滤条件
monitor_job_progress() {
    local job_type="$1"
    local max_wait_seconds=3600
    local wait_interval=1
    local waited_seconds=0
    
    log_info "开始监控 $job_type 任务进度..."
    log_info "将每秒检查一次任务状态，直到所有任务完成"
    
    while [ $waited_seconds -lt $max_wait_seconds ]; do
        local current_time=$(date '+%Y-%m-%d %H:%M:%S')
        
        # 使用当前时间过滤，而不是自然日
        local progress_sql="SELECT START_TIME, TENANT_ID, JOB_ID, JOB_STATUS, PROGRESS 
                           FROM oceanbase.DBA_OB_TENANT_JOBS 
                           WHERE JOB_TYPE = '$job_type' 
                           AND START_TIME >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
                           ORDER BY START_TIME DESC;"
        
        # 检查未完成的任务
        local incomplete_sql="SELECT 1
                           FROM oceanbase.DBA_OB_TENANT_JOBS 
                           WHERE JOB_TYPE = '$job_type'
                           AND START_TIME >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
                           AND JOB_STATUS <> 'SUCCESS';"
        
        local progress_result
        progress_result=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -e "$progress_sql" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            # 始终打印进度信息，不管是否有-l参数
            echo "=== 任务进度监控 (${current_time}) ==="
            echo "$progress_result"
            echo "======================================"
            
            # 检查是否还有未完成的任务
            local incomplete_result
            incomplete_result=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -N -e "$incomplete_sql" 2>/dev/null)
            
            if [ -z "$incomplete_result" ]; then
                log_success "所有 $job_type 任务已完成"
                return 0
            else
                log_info "仍有任务未完成，继续监控..."
            fi
        else
            log_error "查询任务进度失败"
        fi
        
        sleep $wait_interval
        waited_seconds=$((waited_seconds + wait_interval))
        
        # 每10秒打印一次等待时间
        if [ $((waited_seconds % 10)) -eq 0 ]; then
            log_info "已等待 ${waited_seconds}秒"
        fi
    done
    
    log_error "任务监控超时（超过 ${max_wait_seconds}秒）"
    return 1
}

# 清理故障节点副本
cleanup_fault_node() {
    log_info "开始清理故障节点副本流程..."
    local start_time=$(date +%s)
    
    # 1. 修改故障节点租户的locality分布
    local locality_sql="SELECT CONCAT(CONCAT(CONCAT(CONCAT('ALTER TENANT ',tenant_name),' locality='''),
                   CASE WHEN substr(locality,9,5) = T2.zone 
                            THEN REPLACE(locality, CONCAT('FULL{1}@',CONCAT(T2.zone,', ')), '')
                        WHEN locality LIKE '%zone1, FULL{1}@zone2, FULL{1}@zone3%' 
                            THEN REPLACE(locality, CONCAT(', FULL{1}@',T2.zone), '')
                        ELSE locality END), ''';') AS alter_sql
      FROM OCEANBASE.DBA_OB_RESOURCE_POOLS T1
      JOIN OCEANBASE.__ALL_UNIT T2
        ON T1.RESOURCE_POOL_ID=T2.RESOURCE_POOL_ID
      JOIN OCEANBASE.DBA_OB_TENANTS T3
        ON T1.TENANT_ID=T3.TENANT_ID
    WHERE T2.SVR_IP = '192.192.33.77'
      AND T3.tenant_type in ('USER','SYS') 
      AND T3.STATUS = 'NORMAL';"
    
    execute_sql_results "$locality_sql" "1. 修改故障节点租户的locality分布" || return 1
    
    # 2. 检查任务进度
    if [ "$TEST_MODE" = false ]; then
        monitor_job_progress "ALTER_TENANT_LOCALITY" || return 1
    fi
    
    # 3. 对于黑屏创建的租户，和sys租户资源进行分裂
    local split_sql="SELECT DISTINCT
           CONCAT('ALTER RESOURCE POOL ',NAME,' SPLIT INTO (''',
            REPLACE(REPLACE(ZONE_LIST, 'zone', 
            CONCAT(REPLACE(NAME, 'pool_test_', ''),
            '_zone')), ';', ''','''),''') ON (''',
            REPLACE(ZONE_LIST, ';', ''','''),''');') AS alter_sql
     FROM OCEANBASE.DBA_OB_RESOURCE_POOLS T1
     JOIN OCEANBASE.__ALL_UNIT T2 ON T1.RESOURCE_POOL_ID = T2.RESOURCE_POOL_ID
    WHERE ZONE_LIST LIKE '%;%'
      AND T2.SVR_IP = '192.192.33.77';"
    
    execute_sql_results "$split_sql" "3. 分裂黑屏创建的租户和sys租户资源" || return 1
    
    # 4. 修改租户资源池
    local resource_pool_sql="SELECT CONCAT('ALTER TENANT ',
                  T3.TENANT_NAME,
                  ' resource_pool_list=(',GROUP_CONCAT(CONCAT('\\'', T1.NAME, '\\'') 
                                  ORDER BY T1.NAME SEPARATOR ','),');') AS alter_sql
      FROM OCEANBASE.DBA_OB_RESOURCE_POOLS T1
      JOIN OCEANBASE.__ALL_UNIT T2
        ON T1.RESOURCE_POOL_ID=T2.RESOURCE_POOL_ID
      JOIN OCEANBASE.DBA_OB_TENANTS T3
        ON T1.TENANT_ID=T3.TENANT_ID
    WHERE T2.SVR_IP <> '192.192.33.77'
    GROUP BY T3.TENANT_NAME;"
    
    execute_sql_results "$resource_pool_sql" "4. 修改租户资源池" || return 1
    
    # 5. 删除故障节点上的资源池
    local drop_pool_sql="SELECT CONCAT(CONCAT('DROP RESOURCE POOL IF EXISTS ',NAME),';') as alter_sql
    FROM OCEANBASE.DBA_OB_RESOURCE_POOLS T1
     JOIN OCEANBASE.__ALL_UNIT T2
      ON T1.RESOURCE_POOL_ID=T2.RESOURCE_POOL_ID
    WHERE SVR_IP = '192.192.33.77';"
    
    execute_sql_results "$drop_pool_sql" "5. 删除故障节点上的资源池" || return 1
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    log_success "故障节点租户副本清理完成 - 总耗时: ${total_duration}秒"
    log_info "请到OCP平台删除故障节点IP $FAULT_IP，然后重新安装故障节点"
    log_info "重新安装完成后，请运行此脚本选择选项2来重建租户副本"
    
    return 0
}

# 重建故障节点副本
rebuild_fault_node() {
    log_info "开始重建故障节点副本流程..."
    local start_time=$(date +%s)
    
    # 1. 验证新节点添加结果
    log_info "1. 验证新节点添加结果..."
    local verify_sql="SELECT '新节点添加成功'
      FROM OCEANBASE.DBA_OB_SERVERS
     WHERE STATUS='ACTIVE'
    GROUP BY STATUS
    HAVING MAX(CREATE_TIME)>(SELECT MAX(gmt_create) 
                               FROM OCEANBASE.__ALL_ROOTSERVICE_JOB T1
                              WHERE JOB_TYPE = 'DELETE_SERVER'
                                AND progress=100
                                AND job_status='SUCCESS');"
    
    execute_sql "$verify_sql" "验证新节点添加结果" || return 1
    
    # 2. 创建RESOURCE_POOL
    local create_pool_sql="SELECT CONCAT('create resource pool ',
           REPLACE(CONCAT(SUBSTRING_INDEX(T2.NAME, '_zone', 1),'_zone',
                          SUBSTRING_INDEX(SUBSTRING_INDEX(T2.NAME, '_zone', -1), '_', 1),'_',
                          SUBSTRING_INDEX(T2.NAME, '_', -1) ),'config_', 'pool_'),
           ' unit=',T2.NAME,',unit_num=1,zone_list=(''',REGEXP_SUBSTR(T2.NAME, 'zone[0-9]+'),''');') as alter_sql
     FROM OCEANBASE.DBA_OB_RESOURCE_POOLS T1
    RIGHT JOIN OCEANBASE.DBA_OB_UNIT_CONFIGS T2
      ON SUBSTRING(REPLACE(T1.NAME, 'pool_', ''), 1, LOCATE('_zone', REPLACE(T1.NAME, 'pool_', '')) - 1)
       = SUBSTRING(REPLACE(T2.NAME, 'config_', ''), 1, LOCATE('_zone', REPLACE(T2.NAME, 'config_', '')) - 1)
      AND T2.NAME LIKE CONCAT('%', T1.ZONE_LIST, '%')
    WHERE LENGTH(SUBSTRING(REPLACE(T2.NAME, 'config_', ''), 1, LOCATE('_zone', REPLACE(T2.NAME, 'config_', '')) - 1))>=1
      AND T1.NAME IS NULL;"
    
    execute_sql_results "$create_pool_sql" "2. 创建RESOURCE_POOL" || return 1
    
    # 3. 修改租户资源池
    local alter_pool_sql="SELECT CONCAT('ALTER TENANT ',
               SUBSTRING(REPLACE(T1.NAME, 'pool_', ''), 1, LOCATE('_zone', REPLACE(T1.NAME, 'pool_', '')) - 1),
              ' resource_pool_list=(''',GROUP_CONCAT(NAME ORDER BY T1.ZONE_LIST SEPARATOR ''','''),''');') AS alter_sql
    FROM OCEANBASE.DBA_OB_RESOURCE_POOLS T1
     JOIN OCEANBASE.__ALL_UNIT T2
      ON T1.RESOURCE_POOL_ID=T2.RESOURCE_POOL_ID
    WHERE LENGTH(SUBSTRING(REPLACE(T1.NAME, 'pool_', ''), 1, LOCATE('_zone', REPLACE(T1.NAME, 'pool_', '')) - 1))>=1
    GROUP BY SUBSTRING(REPLACE(T1.NAME, 'pool_', ''), 1, LOCATE('_zone', REPLACE(T1.NAME, 'pool_', '')) - 1);"
    
    execute_sql_results "$alter_pool_sql" "3. 修改租户资源池" || return 1
    
    # 4. 修改租户的locality分布
    local alter_locality_sql="SELECT CONCAT(CONCAT('alter tenant ',T3.TENANT_NAME,' locality='''),
               CONCAT(T3.LOCALITY,', FULL{1}@',T1.ZONE_LIST),''';') as alter_sql
      FROM OCEANBASE.DBA_OB_RESOURCE_POOLS T1
      JOIN OCEANBASE.__ALL_UNIT T2
        ON T1.RESOURCE_POOL_ID=T2.RESOURCE_POOL_ID
      JOIN OCEANBASE.DBA_OB_TENANTS T3
        ON T1.TENANT_ID=T3.TENANT_ID
    WHERE T2.SVR_IP = '192.192.33.77'
      AND T3.tenant_type in ('USER','SYS') 
      AND T3.STATUS = 'NORMAL';"
    
    execute_sql_results "$alter_locality_sql" "4. 修改租户的locality分布" || return 1
    
    # 5. 检查任务进度
    if [ "$TEST_MODE" = false ]; then
        monitor_job_progress "ALTER_TENANT_LOCALITY" || return 1
    fi
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    log_success "故障节点租户副本重建完成 - 总耗时: ${total_duration}秒"
    return 0
}

# 主函数
main() {
    log_info "OceanBase故障节点管理脚本启动"
    log_info "日志文件: $LOG_FILE"
    
    if [ "$TEST_MODE" = true ]; then
        log_info "SQL输出文件: $SQL_OUTPUT_FILE"
        echo "-- OceanBase故障节点管理脚本生成的SQL" > "$SQL_OUTPUT_FILE"
        echo "-- 生成时间: $(date)" >> "$SQL_OUTPUT_FILE"
        echo "-- 故障节点IP: $FAULT_IP" >> "$SQL_OUTPUT_FILE"
        echo "" >> "$SQL_OUTPUT_FILE"
    fi
    
    # 解析命令行参数
    parse_arguments "$@"
    
    # 获取数据库连接信息
    get_db_connection
    
    # 获取故障节点IP
    get_fault_ip
    
    # 选择操作
    select_operation
    
    # 根据选择执行相应操作
    case $OPERATION in
        1)
            cleanup_fault_node
            ;;
        2)
            rebuild_fault_node
            ;;
        *)
            log_error "无效的操作选择"
            exit 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log_success "操作执行完成"
        if [ "$TEST_MODE" = true ]; then
            log_info "生成的SQL已保存到: $SQL_OUTPUT_FILE"
        fi
        log_info "详细日志已保存到: $LOG_FILE"
    else
        log_error "操作执行失败"
        exit 1
    fi
}

# 脚本入口
if [ $# -gt 0 ]; then
    while getopts "tlh" opt; do
        case $opt in
            t) TEST_MODE=true ;;
            l) VERBOSE_LOG=true ;;
            h) usage; exit 0 ;;
            *) usage; exit 1 ;;
        esac
    done
fi

# 检查是否安装了mysql客户端
if ! command -v mysql &> /dev/null; then
    echo "错误: 未找到mysql客户端命令，请先安装MySQL客户端"
    exit 1
fi

# 运行主函数
main "$@"
