#!/bin/bash

# 检查是否提供了一个路径参数
if [ "$#" -ne 1 ]; then
    echo "使用方法: $0 <路径>"
    exit 1
fi

# 存储输入的路径
path="$1"

python fa.py "$path" | jq -M -r '.choices[0].message.content'


# 示例使用
# 假设你要基于一个示例文件创建中文版
# create_cn_version "/path/to/your/original_file.txt"