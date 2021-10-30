#!/usr/bin/env bash

# config_dir_path="/opt/k8s-pv-backup/config"
# cache_dir_path="/opt/k8s-pv-backup/data/cache"
config_dir_path="test/config"
cache_dir_path="test/data/cache"
mkdir -p "${config_dir_path}"
mkdir -p "${cache_dir_path}"




# 1. 每隔一段时间就记录一次所有配置文件的 md5 值到 cache 文件中
# 2. 只保留两次所有配置文件的 md5 值记录
# 3. md5 值记录文件被读取成 shell dict
# 4. 计算 cache 文件的 md5 值，如果 md5 值不同，则是配置文件发生了修改
function check_file {
    # 1. 每隔指定时间就记录一次所有配置文件的 md5 值到 cache 文件中
    while true; do
        find "${config_dir_path}" -type f ! -name global ! -name '.*' -exec md5sum {} \; | \
            sort -k 2 | awk '{printf "%s  %s\n",$2,$1}' > ${cache_dir_path}/$(date +%s)
        mapfile file_list < <(ls -t ${cache_dir_path})
        if [[ "${#file_list[@]}" -ge 2 ]]; then break; fi
    done

    # 2. 只保留两次所有配置文件的 md5 值记录
    file_num=2
    for (( count=${file_num}; count<"${#file_list[@]}"; count++ )); do
        rm -rf ${cache_dir_path}/${file_list[count]}
    done
    mapfile file_list < <(ls -t ${cache_dir_path})

    new_file=${file_list[0]}
    old_file=${file_list[1]}
    # declare -p file_list
    # echo "${file_list[@]}";
    # echo -e "new_file: ${new_file}"
    # echo -e "old_file: ${old_file}"


    # 3. md5 值记录文件被读取成 shell dict
    # declare -A new_file_dict old_file_dict
    while read -r key value; do
        new_file_dict[${key}]=${value}
    done < ${cache_dir_path}/${new_file}
    while read -r key value; do
        old_file_dict[${key}]=${value}
    done < ${cache_dir_path}/${old_file}

    # 4. 计算 cache 文件的 md5 值，如果 md5 值不同，则是配置文件发生了修改
    new_file_md5=$(md5sum ${cache_dir_path}/${new_file} | awk '{print $1}')
    old_file_md5=$(md5sum ${cache_dir_path}/${old_file} | awk '{print $1}')
}


function delete_file {
    echo "===== [$(date "+%Y-%m-%d %H:%M:%S")] delete file ====="
    for new_key in "${!new_file_dict[@]}"; do
        unset old_file_dict["$new_key"]
    done
    echo "delete file ${!old_file_dict[@]}"

}
function modified_file {
    echo "===== [$(date "+%Y-%m-%d %H:%M:%S")] modified file ====="
    for key in "${!new_file_dict[@]}"; do
        if [[ ${new_file_dict["$key"]} != ${old_file_dict["$key"]} ]]; then
            echo "modified ${key}"
        fi
    done
}
function create_file {
    echo "===== [$(date "+%Y-%m-%d %H:%M:%S")] create file ====="
    for old_key in "${!old_file_dict[@]}"; do
        unset new_file_dict["$old_key"]
    done
    echo "create file ${!new_file_dict[@]}"
}

sleep_time=5
while true; do
    unset new_file_dict old_file_dict
    declare -A new_file_dict old_file_dict
    check_file

    if [[ ${new_file_md5} == "${old_file_md5}" ]]; then
        echo "===== [$(date "+%Y-%m-%d %H:%M:%S")] no change ====="
        sleep ${sleep_time}
        continue
    fi

    if [[ ${#new_file_dict[@]} -eq ${#old_file_dict[@]} ]]; then 
        modified_file
    elif [[ ${#new_file_dict[@]} -gt ${#old_file_dict[@]} ]]; then
        create_file
    elif [[ ${#new_file_dict[@]} -lt ${#old_file_dict[@]} ]]; then
        delete_file
    fi
    sleep ${sleep_time}
done
