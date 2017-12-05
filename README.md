# clear-disk
历史日志清理脚本

脚本根据配置的日志路径和文件名通配符进行匹配，当磁盘使用量超过limit.conf中配置的百分比阈值后，旧的日志将被清理。

## 使用方式

### 配置

conf/clear.conf
#
# 清空文件:  clear    <size(in k)>  <dir pattern>  <file pattern>
# 删除文件: delete   <1(default in day)|6h|30m>  <dir pattern>  <file pattern>
# 示例:
#   delete 12h      /usr/local/log/*/   foo*.log
#   clear  1000000  /usr/local/app/log/ foo*.log
##################################################################################

# <operation>  <parameters>   <dir pattern>  <file pattern>
delete 10 /var/log/elasticsearch/ *.log.*
delete 10 /var/log/hbase/ *.log.*
delete 10 /var/log/hbase/ *.out.*

### 执行清理
bin/clear_disk.sh
