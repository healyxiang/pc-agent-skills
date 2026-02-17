#!/bin/bash
#
# extract-photos.sh - 从 Apple Photos 库中按月份/日期范围提取照片
#
# 用法:
#   ./extract-photos.sh 2025-03                              # 提取 2025年3月 的所有照片
#   ./extract-photos.sh 2025-03-01 2025-03-15                # 提取日期范围内的照片
#   ./extract-photos.sh --person 赵铁柱 2025-03              # 只提取指定人物的照片
#   ./extract-photos.sh --person 赵铁柱 2025-03-01 2025-03-15
#   ./extract-photos.sh --list-persons                       # 列出所有已命名的人物
#
# 安全保证:
#   - 只读访问 Photos 数据库（复制到临时文件再查询）
#   - 只复制照片，绝不移动或删除原始文件
#   - 同名文件采用覆盖策略
#

set -euo pipefail

# ==================== 配置 ====================
PHOTOS_LIB="$HOME/Pictures/Photos Library.photoslibrary"
PHOTOS_DB="$PHOTOS_LIB/database/Photos.sqlite"
ORIGINALS_DIR="$PHOTOS_LIB/originals"
OUTPUT_BASE_DIR="${OUTPUT_DIR:-.}"  # 默认输出到当前目录，可通过环境变量 OUTPUT_DIR 覆盖

# macOS Core Data epoch offset (2001-01-01 vs 1970-01-01)
CORE_DATA_EPOCH=978307200

# ==================== 参数解析 ====================
PERSON_NAME=""

usage() {
    echo ""
    echo "📷 extract-photos - 从 Apple Photos 库中提取照片"
    echo ""
    echo "用法:"
    echo "  $0 <YYYY-MM>                                     提取指定月份的所有照片"
    echo "  $0 <YYYY-MM-DD> <YYYY-MM-DD>                     提取日期范围内的照片"
    echo "  $0 --person <人物名> <YYYY-MM>                    提取指定人物在某月的照片"
    echo "  $0 --person <人物名> <YYYY-MM-DD> <YYYY-MM-DD>   提取指定人物在日期范围内的照片"
    echo "  $0 --list-persons                                 列出 Photos 中所有已命名的人物"
    echo "  $0 -h | --help                                    显示此帮助信息"
    echo ""
    echo "参数说明:"
    echo "  YYYY-MM          月份格式，如 2025-03，提取该月1日到月末的所有照片"
    echo "  YYYY-MM-DD       日期格式，如 2025-03-01，需要成对使用指定起止范围"
    echo "  --person <名字>  按人脸识别筛选，只提取包含该人物的照片"
    echo "  --list-persons   查看 Photos 库中所有已识别并命名的人物及其照片数量"
    echo ""
    echo "示例:"
    echo "  $0 2025-03                                  # 提取 2025年3月全部照片"
    echo "  $0 2025-03-01 2025-03-15                    # 提取 3月1日 ~ 3月15日"
    echo "  $0 --person 赵铁柱 2025-03                   # 提取 赵铁柱 在2025年3月的照片"
    echo "  $0 --person 赵铁柱 2025-03-01 2025-03-15    # 提取 赵铁柱 在指定范围的照片"
    echo "  $0 --list-persons                            # 列出所有人物名称"
    echo ""
    echo "环境变量:"
    echo "  OUTPUT_DIR  自定义输出目录（默认为当前目录）"
    echo ""
    echo "说明:"
    echo "  - 照片会转换为 JPG 格式保存，视频保留原格式"
    echo "  - 输出到以月份命名的文件夹（如 2025-03/）"
    echo "  - 按人物提取时文件夹格式为 人物名_月份（如 赵铁柱_2025-03/）"
    echo "  - 只读访问 Photos 数据库，绝不修改或删除原始照片"
    echo ""
    exit 0
}

# 处理 -h / --help
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
fi

# 处理 --list-persons
if [ "${1:-}" = "--list-persons" ]; then
    if [ ! -f "$PHOTOS_DB" ]; then
        echo "错误: 找不到 Photos 数据库: $PHOTOS_DB"
        exit 1
    fi
    TMP_DIR_LIST=$(mktemp -d /tmp/photos_list_XXXXXX)
    TMP_DB_LIST="$TMP_DIR_LIST/Photos.sqlite"
    cp "$PHOTOS_DB" "$TMP_DB_LIST" 2>/dev/null
    cp "${PHOTOS_DB}-wal" "${TMP_DB_LIST}-wal" 2>/dev/null || true
    cp "${PHOTOS_DB}-shm" "${TMP_DB_LIST}-shm" 2>/dev/null || true
    echo "Apple Photos 中已命名的人物:"
    echo "========================================="
    echo "名称                    | 照片数"
    echo "-----------------------------------------"
    sqlite3 "$TMP_DB_LIST" "SELECT ZDISPLAYNAME, ZFACECOUNT FROM ZPERSON WHERE ZDISPLAYNAME IS NOT NULL AND ZDISPLAYNAME <> '' ORDER BY ZFACECOUNT DESC;" | while IFS='|' read -r name count; do
        printf "%-24s| %s\n" "$name" "$count"
    done
    echo "========================================="
    rm -rf "$TMP_DIR_LIST"
    exit 0
fi

# 处理 --person 参数
if [ "${1:-}" = "--person" ]; then
    if [ $# -lt 3 ]; then
        echo "错误: --person 需要指定人物名和日期"
        usage
    fi
    PERSON_NAME="$2"
    shift 2
fi

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
fi

# 解析日期参数
if [ $# -eq 1 ]; then
    # 单参数: YYYY-MM 格式，提取整个月
    if [[ ! "$1" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
        echo "错误: 月份格式应为 YYYY-MM，例如 2025-03"
        exit 1
    fi
    YEAR_MONTH="$1"
    # 计算该月的起止日期
    START_DATE="${YEAR_MONTH}-01"
    # 获取下个月的第一天
    if [[ "${YEAR_MONTH:5:2}" == "12" ]]; then
        NEXT_YEAR=$((${YEAR_MONTH:0:4} + 1))
        END_DATE="${NEXT_YEAR}-01-01"
    else
        NEXT_MONTH=$(printf "%02d" $((10#${YEAR_MONTH:5:2} + 1)))
        END_DATE="${YEAR_MONTH:0:5}${NEXT_MONTH}-01"
    fi
    FOLDER_NAME="$YEAR_MONTH"
else
    # 双参数: YYYY-MM-DD YYYY-MM-DD 格式
    if [[ ! "$1" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]]; then
        echo "错误: 起始日期格式应为 YYYY-MM-DD，例如 2025-03-01"
        exit 1
    fi
    if [[ ! "$2" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]]; then
        echo "错误: 结束日期格式应为 YYYY-MM-DD，例如 2025-03-15"
        exit 1
    fi
    START_DATE="$1"
    # 结束日期 +1 天，使范围包含结束日期当天
    END_DATE=$(date -j -v+1d -f "%Y-%m-%d" "$2" "+%Y-%m-%d" 2>/dev/null)
    if [ -z "$END_DATE" ]; then
        echo "错误: 无法解析结束日期 $2"
        exit 1
    fi
    # 文件夹名用起止月份
    START_MONTH="${1:0:7}"
    END_MONTH="${2:0:7}"
    if [ "$START_MONTH" == "$END_MONTH" ]; then
        FOLDER_NAME="$START_MONTH"
    else
        FOLDER_NAME="${START_MONTH}_to_${END_MONTH}"
    fi
fi

# ==================== 前置检查 ====================
if [ ! -f "$PHOTOS_DB" ]; then
    echo "错误: 找不到 Photos 数据库: $PHOTOS_DB"
    echo "请确保 Apple Photos 库位于默认位置"
    exit 1
fi

if ! command -v sqlite3 &>/dev/null; then
    echo "错误: 需要 sqlite3 命令"
    exit 1
fi

if ! command -v sips &>/dev/null; then
    echo "错误: 需要 sips 命令（macOS 内置工具）"
    exit 1
fi

# ==================== 复制数据库（只读访问） ====================
echo "正在准备数据库（只读副本）..."
TMP_DIR=$(mktemp -d /tmp/photos_extract_XXXXXX)
TMP_DB="$TMP_DIR/Photos.sqlite"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$PHOTOS_DB" "$TMP_DB" 2>/dev/null
# 同时复制 WAL 和 SHM 文件，确保数据完整
cp "${PHOTOS_DB}-wal" "${TMP_DB}-wal" 2>/dev/null || true
cp "${PHOTOS_DB}-shm" "${TMP_DB}-shm" 2>/dev/null || true
if [ ! -f "$TMP_DB" ]; then
    echo "错误: 无法复制 Photos 数据库。请确保照片应用未被锁定。"
    exit 1
fi

# ==================== 查询照片 ====================
if [ -n "$PERSON_NAME" ]; then
    echo "正在查询 $START_DATE 到 $END_DATE 之间【${PERSON_NAME}】的照片..."
else
    echo "正在查询 $START_DATE 到 $END_DATE 之间的照片..."
fi

# 将日期转换为 Core Data timestamp
START_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "${START_DATE} 00:00:00" "+%s" 2>/dev/null)
END_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "${END_DATE} 00:00:00" "+%s" 2>/dev/null)

if [ -z "$START_TS" ] || [ -z "$END_TS" ]; then
    echo "错误: 日期转换失败"
    exit 1
fi

START_CORE_DATA=$((START_TS - CORE_DATA_EPOCH))
END_CORE_DATA=$((END_TS - CORE_DATA_EPOCH))

if [ -n "$PERSON_NAME" ]; then
    # 按人物筛选: 通过 ZDETECTEDFACE 和 ZPERSON 表 JOIN
    QUERY="SELECT DISTINCT A.ZDIRECTORY, A.ZFILENAME, datetime(A.ZDATECREATED + $CORE_DATA_EPOCH, 'unixepoch', 'localtime') as date_created, COALESCE(AA.ZORIGINALFILENAME, A.ZFILENAME)
FROM ZASSET A
LEFT JOIN ZADDITIONALASSETATTRIBUTES AA ON AA.ZASSET = A.Z_PK
INNER JOIN ZDETECTEDFACE F ON F.ZASSETFORFACE = A.Z_PK
INNER JOIN ZPERSON P ON F.ZPERSONFORFACE = P.Z_PK
WHERE P.ZDISPLAYNAME = '${PERSON_NAME}'
  AND A.ZDATECREATED >= $START_CORE_DATA
  AND A.ZDATECREATED < $END_CORE_DATA
  AND A.ZTRASHEDDATE IS NULL
  AND A.ZDIRECTORY IS NOT NULL
  AND A.ZFILENAME IS NOT NULL
ORDER BY A.ZDATECREATED ASC;"
else
    # 不筛选人物: 原始查询
    QUERY="SELECT A.ZDIRECTORY, A.ZFILENAME, datetime(A.ZDATECREATED + $CORE_DATA_EPOCH, 'unixepoch', 'localtime') as date_created, COALESCE(AA.ZORIGINALFILENAME, A.ZFILENAME)
FROM ZASSET A
LEFT JOIN ZADDITIONALASSETATTRIBUTES AA ON AA.ZASSET = A.Z_PK
WHERE A.ZDATECREATED >= $START_CORE_DATA
  AND A.ZDATECREATED < $END_CORE_DATA
  AND A.ZTRASHEDDATE IS NULL
  AND A.ZDIRECTORY IS NOT NULL
  AND A.ZFILENAME IS NOT NULL
ORDER BY A.ZDATECREATED ASC;"
fi

# 执行查询
RESULTS=$(sqlite3 "$TMP_DB" "$QUERY" 2>&1) || {
    echo "数据库查询失败: $RESULTS"
    exit 1
}

if [ -z "$RESULTS" ]; then
    echo "未找到该时间段内的照片。"
    exit 0
fi

TOTAL=$(echo "$RESULTS" | wc -l | tr -d ' ')
echo "找到 $TOTAL 张照片/视频。"

# ==================== 创建输出目录 ====================
if [ -n "$PERSON_NAME" ]; then
    FOLDER_NAME="${PERSON_NAME}_${FOLDER_NAME}"
fi
OUTPUT_DIR_FULL="$OUTPUT_BASE_DIR/$FOLDER_NAME"
mkdir -p "$OUTPUT_DIR_FULL"
echo "输出目录: $OUTPUT_DIR_FULL"

# ==================== 复制并转换照片 ====================
COUNT=0
SKIP=0
FAIL=0

echo ""
echo "开始提取照片..."

while IFS='|' read -r DIR FILENAME DATE_CREATED ORIG_FILENAME; do
    COUNT=$((COUNT + 1))
    SRC="$ORIGINALS_DIR/$DIR/$FILENAME"

    if [ ! -f "$SRC" ]; then
        echo "  [$COUNT/$TOTAL] 跳过（文件不存在）: $FILENAME"
        SKIP=$((SKIP + 1))
        continue
    fi

    # 获取文件扩展名（小写）
    EXT=$(echo "${FILENAME##*.}" | tr '[:upper:]' '[:lower:]')

    # 使用原始相机文件名（如 IMG_5064），如果没有则回退到库文件名
    if [ -n "$ORIG_FILENAME" ]; then
        DISPLAY_NAME="${ORIG_FILENAME%.*}"
    else
        DISPLAY_NAME="${FILENAME%.*}"
    fi

    # 提取拍摄日期（从 "2026-02-17 14:30:00" 中取 "2026-02-17"）
    PHOTO_DATE="${DATE_CREATED%% *}"

    # 构造输出文件名: 日期_原始名.ext
    OUTPUT_NAME="${PHOTO_DATE}_${DISPLAY_NAME}"

    # 根据文件类型处理
    case "$EXT" in
        heic|heif|png|tiff|tif|bmp|gif)
            # 需要转换为 JPG
            OUTPUT_FILE="$OUTPUT_DIR_FULL/${OUTPUT_NAME}.jpg"
            echo "  [$COUNT/$TOTAL] 转换: $FILENAME -> ${OUTPUT_NAME}.jpg"
            if ! sips -s format jpeg -s formatOptions 90 "$SRC" --out "$OUTPUT_FILE" &>/dev/null; then
                echo "    警告: 转换失败: $FILENAME"
                FAIL=$((FAIL + 1))
                continue
            fi
            ;;
        jpg|jpeg)
            # 已经是 JPG，直接复制
            OUTPUT_FILE="$OUTPUT_DIR_FULL/${OUTPUT_NAME}.jpg"
            echo "  [$COUNT/$TOTAL] 复制: $FILENAME -> ${OUTPUT_NAME}.jpg"
            if ! cp "$SRC" "$OUTPUT_FILE" 2>/dev/null; then
                echo "    警告: 复制失败: $FILENAME"
                FAIL=$((FAIL + 1))
                continue
            fi
            ;;
        mp4|mov|m4v|avi)
            # 视频文件，直接复制（不转换格式）
            OUTPUT_FILE="$OUTPUT_DIR_FULL/${OUTPUT_NAME}.${EXT}"
            echo "  [$COUNT/$TOTAL] 复制视频: $FILENAME -> ${OUTPUT_NAME}.${EXT}"
            if ! cp "$SRC" "$OUTPUT_FILE" 2>/dev/null; then
                echo "    警告: 复制失败: $FILENAME"
                FAIL=$((FAIL + 1))
                continue
            fi
            ;;
        *)
            # 其他格式，直接复制
            OUTPUT_FILE="$OUTPUT_DIR_FULL/${OUTPUT_NAME}.${EXT}"
            echo "  [$COUNT/$TOTAL] 复制: $FILENAME -> ${OUTPUT_NAME}.${EXT}"
            if ! cp "$SRC" "$OUTPUT_FILE" 2>/dev/null; then
                echo "    警告: 复制失败: $FILENAME"
                FAIL=$((FAIL + 1))
                continue
            fi
            ;;
    esac
done <<< "$RESULTS"

# ==================== 结果汇总 ====================
SUCCESS=$((COUNT - SKIP - FAIL))
echo ""
echo "========================================="
echo "提取完成!"
if [ -n "$PERSON_NAME" ]; then
    echo "  人物: $PERSON_NAME"
fi
echo "  总计: $TOTAL 个文件"
echo "  成功: $SUCCESS"
echo "  跳过: ${SKIP:-0}（文件不存在，可能在 iCloud 未下载）"
echo "  失败: ${FAIL:-0}"
echo "  输出目录: $OUTPUT_DIR_FULL"
echo "========================================="
