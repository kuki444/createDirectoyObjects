#!/usr/bin/env bash

# サイト名（環境名）
site_name=${2,,}

#
product_sub_path='/'
# スキーマ名
schema_name=${site_name^^}
# フォルダ検索パス　# todo 環境に合わせる
find_path="./${site_name}/log"
# 固定フォルダ定義 @todo 固定分設定
array_path=(
  'download'
  'upload'
)
# 編集用出力ファイル
## ディレクトリオブジェクト作成DDL
dir_list_file=$(mktemp)
## ディレクトオブジェクト削除SQL
dir_del_file=$(mktemp)

# 生成した一時ファイルを削除する
function rm_tmpfile {
  [[ -f "${dir_list_file}" ]] && rm -f "${dir_list_file}"
  [[ -f "${dir_del_file}" ]] && rm -f "${dir_del_file}"
}
# 正常終了したとき
trap rm_tmpfile EXIT
# 異常終了したとき
trap 'trap - EXIT; rm_tmpfile; exit -1' INT PIPE TERM

cat  <<EOF > ${dir_del_file}
SET ECHO OFF;
SET LINESIZE 1000;
SET HEADING OFF;
SET UNDERLINE OFF;
SET PAGESIZE 0;
SET TRIMSPOOL ON;
SET FEEDBACK OFF;
SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT 9
DECLARE
  CURSOR DIRECTORY_LIST_CUR IS
    SELECT DIRECTORY_NAME
      FROM ALL_DIRECTORIES
     WHERE DIRECTORY_NAME LIKE '${schema_name}%';

  DIRECTORY_LIST_REC DIRECTORY_LIST_CUR%ROWTYPE;
BEGIN
  OPEN DIRECTORY_LIST_CUR;
  LOOP
    FETCH DIRECTORY_LIST_CUR INTO DIRECTORY_LIST_REC;
    EXIT WHEN DIRECTORY_LIST_CUR%NOTFOUND;
    EXECUTE IMMEDIATE 'DROP DIRECTORY '  || DIRECTORY_LIST_REC.DIRECTORY_NAME;
    DBMS_OUTPUT.PUT_LINE('Drop Directory ' || DIRECTORY_LIST_REC.DIRECTORY_NAME);
  END LOOP;
  CLOSE DIRECTORY_LIST_CUR;
END;
/
EXIT;
EOF

sqlplus sys/oracle as sysdba @${dir_del_file}  > /dev/null 2>&1
#sqlplus sys/oracle as sysdba @${dir_del_file}
ret=$?
if [ ${ret} -ne 0 ]; then
  echo "Oracle Err ErrorCode:${ret}"
  exit ${ret}
fi

# フォルダ検索パス取得
array_path="${array_path[@]} `cd ${find_path};find * -type d `"

# ディレクトリオブジェクト作成SQL編集
echo 'WHENEVER SQLERROR EXIT SQL.SQLCODE' >> ${dir_list_file}
echo 'WHENEVER OSERROR EXIT 9' >> ${dir_list_file}
for dir_path in $array_path; do
  directory_name=${dir_path^^}
  directory_name=${schema_name}_${directory_name//\//_}
  dir_full_path=${product_sub_path}/${site_name}/${dir_path}
  echo "CREATE DIRECTORY ${directory_name} AS '${dir_full_path}';" >> ${dir_list_file}
  echo "GRANT WRITE,READ ON DIRECTORY ${directory_name} TO ${schema_name};" >> ${dir_list_file}
done
echo 'EXIT' >> ${dir_list_file}

# ディレクトリオブジェクト作成
sqlplus sys/oracle as sysdba @${dir_list_file} > /dev/null 2>&1
#sqlplus sys/oracle as sysdba @${dir_list_file}
ret=$?
if [ ${ret} -ne 0 ]; then
  echo "Oracle Err ErrorCode:${ret}"
  exit ${ret}
fi

# 完了メッセージ
echo "Oracle DirectoyObjects Create Success ${site_name}"
