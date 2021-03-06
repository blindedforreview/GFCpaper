							### Data Prep 2003 ###

## Package Load
library(RSQLite)
library(magrittr)
library(survey)
library(Amelia)
library(mitools)
library(parallel)
#-------------------------------------------------

## Extract data from SQL database
db <- dbConnect(SQLite(), dbname="~/Dropbox/Databases/SQLdb/LSAY2015_update.db")
#-------------------------------------------------

## Extract 2003 well-being data
	# Meta File extraction of target variables
	m2003 <- dbGetQuery(db, "SELECT * FROM LSAYMETA where cohort = 'Y03'")
	lsTags <- m2003[grep("Life satisfaction", m2003$Minor.topic.area),]

	# Exclusion of ecopnomy and politics questions as not consistently present
	lsTags <- lsTags[-c(grep("country|economy", lsTags$Data.element)),]

	# Extract Weight  variables
	weightTags <- m2003[grep("Final weight 20(04|05|06|07|08|09|10|11|12|13)$",
							 m2003$Label),]

	# Extraction of major data
	query <- paste("SELECT ", paste(lsTags$Variable, collapse=","),",", 
				   paste(weightTags$Variable, collapse=","),
				   " ,SCHOOLID, STATEID, SEX, INDIG, HISEI, INTDAT04, DOB FROM LSAY2003")

	d2003 <- dbGetQuery(db, query)
	#remove missing
	d2003$INTDAT04 <- recode(d2003$INTDAT04, "'.'=NA")
	d2003$id <- paste0("C03.",row.names(d2003))
	# Add mining state
	d2003$mining <- recode(d2003$STATEID, "c(4,6,8)=1; c(1,2,3,5,7)=0")
	#Specify age in days at first interview point
	d2003$age <- as.Date(d2003$INTDAT04, "%d/%m/%y") - as.Date(d2003$DOB, "%d/%m/%y")
	# translate to EGP
	source("./lib/translationFun.R")
	translator <- dbGetQuery(db, "SELECT ISEI, EGP FROM SESconversion")
	d2003$EGP <- sesConvert(d2003$HISEI, fromFormat = "ISEI", toFormat = "EGP", FUN = Mode)
	#d2003$EGP <- sapply(d2003$HISEI, function(x) translator[match(x, translator$ISEI), "EGP"] )
	d2003$EGP <- recode(d2003$EGP, "c(1,2)='upper'; c(3,4,5,6,7,8)='middle'; c(9,10,11)='working'") %>% factor %>%
		relevel( 'upper')
	d2003 <- d2003[,-c(136:137)]
#-------------------------------------------------
## Run edit rules
source("./lib/editRules.R")
	# Check data
	names(d2003)[1:120] <- lsTags$smallName 
	#Number don't know
	dk <-round(apply(d2003[,lsTags$smallName],2,function(x) sum(x == 5, na.rm = TRUE)/length(x)),3 )
	range(dk); mean(dk)
	#Check  out of range responses
	if(length(rangeFun(d2003))!=0) {cat("Mistakes in Range Found")}
	#NOT RUN!! rangeFun(d2003)
	# Run frequencies
	d2003[,1:120] <- recodeFun(d2003[,1:120])
	F2003 <- frequencyFun(d2003[,1:120])
	if(dim(F2003)==c(120,4)) {write.csv(F2003, file = "f2003.csv")}

## Get means
M2003 <-apply(d2003[,1:120],2, mean, na.rm=TRUE)
write.csv(M2003, file = "m2003.csv")
#write data for PSMatching
save(d2003, file = "psm2003.RData")
#-------------------------------------------------
## Survey package - Imputation and Replicant Weights
N <- length(d2003)
# Reorder
d2003 <- d2003[,c(order(names(d2003)[1:120]), 121:N)]
names(d2003) <- gsub("(|\\.)[0-9]+", "", names(d2003))
# Rename weight variables
# Stack data
dLong03 <- rbind.data.frame(d2003[,c(1,11,21,31,41,51,61,71,81,91,101,111,121,131:N)], 
							d2003[,c(2,12,22,32,42,52,62,72,82,92,102,112,122,131:N)],
							d2003[,c(3,12,23,33,43,53,63,73,83,93,103,113,123,131:N)], 
							d2003[,c(4,14,24,34,44,54,64,74,84,94,104,114,124,131:N)],
							d2003[,c(5,15,25,35,45,55,65,75,85,95,105,115,125,131:N)],
							d2003[,c(6,16,26,36,46,56,66,76,86,96,106,116,126,131:N)],
							d2003[,c(7,17,27,37,47,57,67,77,87,97,107,117,127,131:N)],
							d2003[,c(8,18,28,38,48,58,68,78,88,98,108,118,128,131:N)],
							d2003[,c(9,19,29,39,49,59,69,79,89,99,109,119,129,131:N)],
							d2003[,c(10,20,30,40,50,60,70,80,90,100,110,120,130,131:N)])
dLong03$trend <- rep(1:10, each=(nrow(d2003)))
# Add treatment variable
dLong03$post06 <- ifelse(dLong03$trend > 3,1,0)
dLong03$post03 <- ifelse(dLong03$trend > 6,1,0)
#add cohort variable
dLong03$cohort <- 'y03'
# List wise delete by attrition
dLong03 <- dLong03[!is.na(dLong03$WT),]
# Check number of complete cases
sum(complete.cases(dLong03))
#Multiple Imputations of data holes
MI <- amelia(dLong03,m = 5, p2s = 1, idvars = c('id', 'WT', 'post03', 'post06', 'cohort', 'STATEID'),
			 noms = c("EGP", "SEX", "INDIG") )
a03 <- imputationList(MI$imputations)
#save to Rdata
save(a03, file = "Cohort03Data.RData")
rm(list=c("dLong03", "d2003", "lsTags", "weightTags", "F2003", "m2003"))
# Wrap in srvey package
dclust <- svydesign(ids = ~id+SCHOOLID, weights = ~WT, data = a03, nest=TRUE)
rm(a)

## Analysis of weighted data
# Set parallel options
options(mc.cores=detectCores())
# Run Means
trendMeans <- MIcombine(with (dclust, 
							  svyby(~general+living+home+future+career+work+
							  	  	money+lesiure+location+social+people+
							  	  	independence, 
							  	  ~trend, svymean, na.rm=TRUE, multicore=TRUE
							  )
)
)
# Wrap means and CIs into table and write to output
S2003 <- cbind(trendMeans$coefficients, confint(trendMeans))
colnames(S2003)[1] <- "means"
write.csv(S2003, file = "s2003.csv")
