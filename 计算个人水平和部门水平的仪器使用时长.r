###################################### 注意事项 #####################################
# 1. 修改工作目录：Session - Set Working Directory - Choose Directory
# 2. （可选）修改文件编码/解码方式： Tools - Global Options - Code -Saving - "gb2312"
# 3. (可选) 以指定解码方式打开文件：File - Reopen with Encoding - "gb2312"
# 4. 如要计算1月1日至1月31日区间内的使用时长，请下载12月28日至2月3日区间的预约表和使用表！
# 5. 请确保“实际使用人”和“实际使用人所属”同时存在！本脚本有检测机制！
#####################################################################################

library(dplyr)
library(ggplot2)

###############################
####### 手动调整部分 ##########
###############################

#### 读入数据 #####
# 读入预约表
reservation.data <- read.delim("reservation (3).txt",stringsAsFactors = FALSE)
head(reservation.data)
# 读入使用表
use.data <- read.delim("ins_use_record (4).txt",stringsAsFactors = FALSE)
head(use.data)

##### 设定时间区间 #####
start <- "2019-11-20 00:00:00"
end <- "2019-12-19 17:59:59"

time.start <- as.POSIXct(start, format="%Y-%m-%d %H:%M:%OS")
time.end <- as.POSIXct(end, format="%Y-%m-%d %H:%M:%OS")


###############################
####### 数据处理部分 ##########
###############################

##### 数据清洗 #####
# 整理预约表，仅保留审核通过的。
reservation.filtered <- filter(reservation.data,审核状态 == "已审核")

# 如果结束使用时间为“”（空），表示尚未结束使用，将结束使用时间设为计算区间的截止时间。
use.data$结束使用[which(use.data$结束使用 == "")] <- end

# 设置数据类型为时间
use.data$开始使用 <- as.POSIXct(use.data$开始使用)
use.data$结束使用 <- as.POSIXct(use.data$结束使用)
reservation.filtered$预约使用时间 <- as.POSIXct(reservation.filtered$预约使用时间)
reservation.filtered$预约结束时间 <- reservation.filtered$预约使用时间 + reservation.filtered$预约使用时长*60

# 预约表中的“待履约”对应的使用时间段肯定不在计算区间内，故去除预约表中的“待履约”条目！
# 待履约：(下载数据时)尚未到达预约起始时间！-  要去除！
# 延迟：(下载数据时)已到达预约时间内，但尚未去使用！
# 爽约： 整个预约时间内，未曾使用！
# 履约中：(下载数据时)尚未到达预约结束时间，仍在使用中！
# 已履约：已完成使用！
if ( "待履约" %in% reservation.filtered$履约状态) {
  print("去除预约表中的“待履约”的条目！")
  reservation.filtered <- filter(reservation.filtered,履约状态 != "待履约")
}

table(reservation.filtered$履约状态)

# 去除不位于计算区间内的“延迟”和“履约中”
reservation.filtered <- filter(reservation.filtered, !(履约状态 == "延迟" & 预约使用时间 > time.end))
reservation.filtered <- filter(reservation.filtered, !(履约状态 == "履约中" & 预约使用时间 > time.end))

# 预约表与使用表进行条目对应- 关键！
# 此步骤会合并一个预约条目对应的多个使用条目！
use.start <- c()
use.end <- c()

for (i in 1:length( reservation.filtered$履约状态 )) {
  # “爽约”条目不会有对应的使用条目
  if ( reservation.filtered$履约状态[i] == "爽约") {
    use.start <- append(use.start,reservation.filtered$预约使用时间[i])
    use.end <- append(use.end,reservation.filtered$预约结束时间[i])
  } 
  else if (reservation.filtered$履约状态[i] == "延迟"){ 
    # 延迟表示该预约为该仪器的最后使用者，并且预约截止时间肯定晚于计算截至时间！
    use.start <- append(use.start,reservation.filtered$预约使用时间[i])
    use.end <- append(use.end,time.end)
  }
  else if (reservation.filtered$履约状态[i] == "已履约"){
    # 过滤使用记录中“开始使用时间”位于预约时间区间内的条目，取开始使用的最小值，结束使用的最大值（可能有多个对应条目）。
    record <- use.data[use.data$设备编号 == reservation.filtered$设备编号[i] & 
                         use.data$使用人 == reservation.filtered$预约人[i] & 
                         use.data$开始使用 >= reservation.filtered$预约使用时间[i] &
                         use.data$开始使用 <= reservation.filtered$预约结束时间[i],]
    use.start <- append(use.start,min(record$开始使用))
    use.end <- append(use.end,max(record$结束使用))
  } 
  else if (reservation.filtered$履约状态[i] == "履约中"){
    # “履约中”对应的使用条目没有结束使用时间，在之前已经设为计算截至时间!
    record <- use.data[use.data$设备编号 == reservation.filtered$设备编号[i] & 
                         use.data$使用人 == reservation.filtered$预约人[i] & 
                         use.data$开始使用 >= reservation.filtered$预约使用时间[i] &
                         use.data$开始使用 <= reservation.filtered$预约结束时间[i],]
    use.start <- append(use.start,min(record$开始使用))
    use.end <- append(use.end,time.end)
  }else {
    print("错误，找不到预约对应的实际使用时间：")
    print(reservation.filtered[i,])
    print("请手动到“使用表”中寻找该“预约条目”对应的“实际使用条目”！")
    stop()
  }
}

data.combined <- reservation.filtered
data.combined$开始使用 <- use.start
data.combined$结束使用 <- use.end
colnames(data.combined)

# 过滤数据，仅保留预约条目或使用条目 与 计算区间有交叉的条目
# 去除全部落去区间右边的
data.combined <- filter(data.combined, !(预约使用时间 > time.end & 开始使用 > time.end))
# 去除全部落去区间左边的
data.combined <- filter(data.combined, !(预约结束时间 < time.start & 结束使用 < time.start))

# 依据仪器和开始使用时间对数据进行排序
data.combined <- arrange(data.combined,设备编号,预约使用时间)

# 判定使用者是否换了仪器！
instrument.change <- c(TRUE)
for (i in 2:length(data.combined$预约使用时间)) {
  if ( data.combined$设备编号[i] ==  data.combined$设备编号[i-1]) {
    instrument.change <- append(instrument.change,FALSE)
  } else {instrument.change <- instrument.change <- append(instrument.change,TRUE) }
}

data.combined$仪器是否更换 <- instrument.change


# 判定前人（非上一人）结束时间，为判定是否因前面人延迟而影响本人的使用（爽约，延迟使用等）！
forward.end <- c()
for (i in 1:length(data.combined$开始使用)) {
  # 如果更换了仪器，记为本人开始使用时间！
  if (data.combined$仪器是否更换[i]) {
    forward.end <- append(forward.end,data.combined$开始使用[i])
    end.use <- data.combined$结束使用[i]
  }else { 
    # 如果没有更换仪器
    # 如果前人结束时间晚于本人预约结束时间
    if ( end.use >= data.combined$结束使用[i]) {
      end.use <- max(end.use,data.combined$结束使用[i])
      forward.end <- append(forward.end,end.use)
    } else { # 前人结束时间早于本人预约结束时间
      forward.end <- append(forward.end,end.use)
      end.use <- data.combined$结束使用[i]
    }
  }
}

data.combined$前人结束时间 <- forward.end

# 判定前人是否影响了本人的开始使用！
# 0:无影响
# 1：仅影响了起始使用时间
# 2：导致无法使用(包括补预约情况！)
effect <- c()
for (i in 1:length(data.combined$开始使用)) {
  # 如果更换了仪器，设为无影响
  if (data.combined$仪器是否更换[i]) {
    effect <- append(effect,0)
  } else if (data.combined$前人结束时间[i] <= data.combined$预约使用时间[i]){ # 无影响
    effect <- append(effect,0)
  } else if (data.combined$前人结束时间[i] <= data.combined$预约结束时间[i]) {# 影响了起始使用 
    effect <- append(effect,1)
  } else if (data.combined$前人结束时间[i] > data.combined$预约结束时间[i]) {# 导致无法使用 
    effect <- append(effect,2)
  }
}

data.combined$受影响等级 <- effect

# 判定实际起始使用时间
pratice.start <- c()
for (i in 1:length(data.combined$设备编号)) {
  if ( data.combined$受影响等级[i] == 0) { # 不受影响的，起始时间为预约使用时间
    pratice.start <- append(pratice.start,data.combined$预约使用时间[i])
  } else if (data.combined$受影响等级[i] == 1){ # 影响等级为1的，起始时间为前人结束时间！
    pratice.start <- append(pratice.start,data.combined$前人结束时间[i])
  } else if(data.combined$受影响等级[i] == 2){ # 影响等级为2的，起始时间为本人的预约结束时间！
    pratice.start <- append(pratice.start,data.combined$预约结束时间[i])
  }
}

data.combined$实际计算起始时间 <- pratice.start

# 修正落于计算区间外的起始时间和结束时间
data.combined$实际计算起始时间[data.combined$实际计算起始时间 < time.start] <- time.start
pratice.end <- c()
for (i in 1:length(data.combined$预约结束时间)) {
  if (data.combined$预约结束时间[i] > data.combined$结束使用[i]) {
    pratice.end <- append(pratice.end,data.combined$预约结束时间[i])
  } else { pratice.end <- append(pratice.end,data.combined$结束使用[i]) }
}
data.combined$实际计算截止时间 <- pratice.end
data.combined$实际计算截止时间[ data.combined$实际计算截止时间 > time.end ] <- time.end 

# 计算使用时长
data.combined$使用总时长 <- round(as.numeric(difftime(data.combined$实际计算截止时间, data.combined$实际计算起始时间,units="mins")),digits = 0)

# 计算该时间段内的预约时长
order.start <- data.combined$预约使用时间
order.start[order.start < time.start ] <- time.start
order.start[order.start > time.end] <- time.end
order.end <- data.combined$预约结束时间
order.end[order.end > time.end ] <- time.end
order.end[order.end < time.start] <- time.start
data.combined$实际预约起始 <- order.start
data.combined$实际预约结束 <- order.end
data.combined$预约总时长 <- round(as.numeric(difftime(data.combined$实际预约结束, data.combined$实际预约起始,units="mins")),digits = 0)

#文件重新排序
results <- select(data.combined,设备编号,
                  仪器名称,
                  分类,
                  位置,
                  预约人,
                  预约部门,
                  实际使用人,
                  实际使用人所属,
                  备注,
                  履约状态,
                  审核状态,
                  预约使用时长,
                  预约使用时间,
                  预约结束时间,
                  开始使用,
                  结束使用,
                  前人结束时间,
                  仪器是否更换,
                  受影响等级,
                  实际计算起始时间,
                  实际计算截止时间,
                  使用总时长,
                  实际预约起始,
                  实际预约结束,
                  预约总时长)

# 判定实际使用人和实际使用人所属 是否同时存在！
equal_exist <- which(results$实际使用人 == "") == which(results$实际使用人所属 == "")
if(length(equal_exist) == sum(equal_exist) ){
  print("实际使用人和实际使用人所属信息同时存在！检查通过！")
} else {
  print("实际使用人和实际使用人所属信息不同时存在！检查未通过！请自行检查最终结果中的实际使用人及其部门信息是否正确！")
}

# 填充实际使用人信息
results$实际使用人[results$实际使用人 == "" ] <- results$预约人[results$实际使用人 == ""]
results$实际使用人所属[results$实际使用人所属 == "" ] <- results$预约部门[results$实际使用人所属 == ""]
head(results)

# 保存文件为CSV格式
write.csv(results,file = paste("时长计算-From-",substring(as.character(time.start),1,10),"-To-",substring(as.character(time.end),1,10),".csv",sep = ""))


# 按照仪器编号和实际使用人所属部门进行分组，计算每个部门对每个仪器的预约总时长和使用总时长
results_merged_department <- group_by(results,设备编号,实际使用人所属,仪器名称,分类,位置) %>%
  summarize(
    预约总时长=sum(as.numeric(预约总时长)),
    使用总时长=sum(as.numeric(使用总时长)))

head(results_merged_department)
write.csv(results_merged_department,file = paste("时长计算-部门水平-From-",substring(as.character(time.start),1,10),"-To-",substring(as.character(time.end),1,10),".csv",sep = ""))

# 按照仪器编号、实际使用人所属部门和实际使用人进行分组，计算单个人对仪器的预约总时长和使用总时长！
results_merged_individual <- group_by(results,设备编号,实际使用人,实际使用人所属,仪器名称,分类,位置) %>%
  summarize(
    预约总时长=sum(as.numeric(预约总时长)),
    使用总时长=sum(as.numeric(使用总时长)))

head(results_merged_individual)
write.csv(results_merged_individual,file = paste("时长计算-个人水平-From-",substring(as.character(time.start),1,10),"-To-",substring(as.character(time.end),1,10),".csv",sep = ""))


###############################################
####### 可选：输出未预约就使用的记录 ##########
###############################################
# 可选一
# 把未预约就使用的也列出来！ 一般不会有此类型的条目！ 如果有，说明系统出错了，有人未预约就使用！
# 过滤使用表: 仅保留落于时间区间内的记录
use.filtered <- use.data[!(use.data$开始使用 > time.end | use.data$结束使用 < time.start),]

index <-c()

for (i in 1:length(use.filtered$开始使用)) {
  tmp.data <- results[ results$设备编号 == use.filtered$设备编号[i] &
                         results$预约人 == use.filtered$使用人[i] &
                         results$预约使用时间 <= use.filtered$开始使用[i] &
                         results$预约结束时间 >= use.filtered$开始使用[i],]
  if (dim(tmp.data)[1] < 1) {
    index <- append(index,i)
  }

}

if (length(index) == 0) {
  print("一切正常，没有未预约就使用的记录！")
}else {
  print("注意！ 以下使用记录未找到对应的预约信息：")
  print(use.filtered[index,])
  write.csv(use.filtered[index,],file = paste("未预约就使用仪器的记录-From-",substring(as.character(time.start),1,10),"-To-",substring(as.character(time.end),1,10),".csv",sep = ""))
}


# 可选二
# 哪些预约条目找不到对应的使用条目，一般是爽约或者延迟！
index <-c()
for (i in 1:length(reservation.filtered$预约使用时间)) {
  tmp.data <- use.filtered[ use.filtered$设备编号 == reservation.filtered$设备编号[i] &
                         use.filtered$使用人 == reservation.filtered$预约人[i] &
                         use.filtered$开始使用 >= reservation.filtered$预约使用时间[i] &
                         use.filtered$开始使用 <= reservation.filtered$预约结束时间[i],]
  if (dim(tmp.data)[1] < 1) {
    index <- append(index,i)
  }

}

if (length(index) == 0) {
  print("一切正常，没有预约条目均能找到对应的使用条目！")
}else {
  print("注意！ 以下使用预约条目未找到对应的使用信息：")
  print(reservation.filtered[index,])
  write.csv(reservation.filtered[index,],file = paste("未找到对应使用记录的预约记录-From-",substring(as.character(time.start),1,10),"-To-",substring(as.character(time.end),1,10),".csv",sep = ""))
}

###############################################
############ 可选：ggplot2 绘图 ###############
###############################################
# ggplot2
# 实验室水平的各个仪器的使用总时长
results_merged_department[,c("设备编号","实际使用人所属","使用总时长")]
ggplot(results_merged_department,mapping= aes(x = as.factor(paste(仪器名称,位置,sep="-")),
                                              y=使用总时长,
                                              fill = as.factor(实际使用人所属)))+
  geom_bar(stat = "identity") +
  xlab("仪器") +
  ylab("使用总时长") +
  scale_fill_discrete(name="实验室") +
  coord_flip()

# 实验室水平的各个仪器的预约总时长
results_merged_department[,c("设备编号","实际使用人所属","预约总时长")]
ggplot(results_merged_department,mapping= aes(x = as.factor(paste(仪器名称,位置,sep="-")),
                                              y=预约总时长,
                                              fill = as.factor(实际使用人所属)))+
  geom_bar(stat = "identity") +
  xlab("仪器") +
  ylab("使用总时长") +
  scale_fill_discrete(name="实验室") +
  coord_flip()