if(!require(caret)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(tidyverse)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(ggplot2)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(infotheo)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(mboost)) install.packages("mboost", repos = "http://cran.us.r-project.org")

library(caret)
library(tidyverse)
library(ggplot2)
library(infotheo)
library(mboost)

# Helper functions
wrangleData <- function(dataset) {
  qualityRateColumns <- c("ExterCond", "ExterQual", "BsmtCond", "BsmtQual", "HeatingQC", "KitchenQual", "FireplaceQu", "GarageQual", "GarageCond", "PoolQC")
  informativeNAColumns <- c("Alley", "MasVnrType", "BsmtExposure", "GarageType", "MiscFeature", "BsmtFinType1", "BsmtFinType2", "Electrical", "GarageFinish", "Fence", "MSZoning", "Utilities", "Exterior1st", "Exterior2nd", "Functional")
  meanIfNAColumns <- c("LotFrontage")
  zeroIfNAColumns <- c("BsmtFinSF1", "BsmtFinSF2", "BsmtUnfSF", "TotalBsmtSF", "BsmtFullBath", "BsmtHalfBath", "GarageCars", "GarageArea", "MasVnrArea", "GarageYrBlt")
  
  # Set numeric rating to factor columns
  for (col in qualityRateColumns) {
    dataset[[col]] <- condQualityToInt(dataset[[col]])
  }
  
  # Add NA factor
  for (col in informativeNAColumns) {
    dataset[[col]] <- addNA(dataset[[col]])
  }
  
  # Set mean instead of NA to the columns that require it
  for (col in meanIfNAColumns) {
    dataset[[col]][which(is.na(dataset[[col]]))] <- mean(dataset[[col]], na.rm = T)
  }
  
  # Set zero instead of NA to the columns that require it
  for (col in zeroIfNAColumns) {
    dataset[[col]][which(is.na(dataset[[col]]))] <- 0
  }
  
  # Convert 2 level factor to numeric col as obviously Y is good and N level is bad
  dataset$CentralAir <- sapply(dataset$CentralAir, yesNoToBinary)
  
  # Set other factor to SaleType if NA
  dataset$SaleType[which(is.na(dataset$SaleType))] <- factor("Oth")
  
  
  # Define overall number of Bathrooms
  dataset$Bathrooms <- dataset$BsmtFullBath+dataset$BsmtHalfBath*0.5+dataset$FullBath+dataset$HalfBath*0.5
  
  dataset$BsmtFinSF <- dataset$BsmtFinSF1 + dataset$BsmtFinSF2
  
  dataset$TotalSquare <- dataset$TotalBsmtSF + dataset$X1stFlrSF + dataset$X2ndFlrSF
  
  # Compute age
  dataset$Age <- dataset$YrSold - dataset$YearBuilt
  # Compute age of renovation
  dataset$SinceRenov <- ifelse(dataset$YrSold - dataset$YearRemodAdd < 0, 0, dataset$YrSold - dataset$YearRemodAdd)
  dataset$GarageAge <- dataset$YrSold - dataset$GarageYrBlt
  
  dataset$Freshness <- dataset$Age * dataset$SinceRenov
  dataset$Newness <- sqrt(dataset$SinceRenov * dataset$GrLivArea)
  
  dataset$New <- ifelse(dataset$Age == 0, 1, 0)
  dataset$Fresh <- ifelse(dataset$SinceRenov == 0, 1, 0)
  
  dataset$Overall <- dataset$OverallCond * dataset$OverallQual
  dataset$ExternalOverall <- dataset$ExterCond * dataset$ExterQual
  dataset$GarageOverall <- dataset$GarageQual * dataset$GarageCond
  
  dataset$LotArea_log <- log(dataset$LotArea)
  
  dataset$Spaciousness <- (dataset$X1stFlrSF + dataset$X2ndFlrSF)/dataset$TotRmsAbvGrd
  
  # COmpute overall porch area
  dataset$PorchArea <- dataset$WoodDeckSF + dataset$OpenPorchSF+ dataset$EnclosedPorch+ dataset$X3SsnPorch+ dataset$ScreenPorch
  
  # Compute WOW effect for basement, garage and house
  dataset$GarageWow <- dataset$GarageArea * dataset$GarageQual * dataset$GarageCond
  dataset$OverallWow <- dataset$OverallQual * dataset$OverallCond * dataset$GrLivArea
  dataset$BasementWow <- dataset$BsmtQual * dataset$BsmtCond * dataset$BsmtFinSF
  
  dataset$SalePrice_Log <- ifelse(is.na(dataset$SalePrice), 0, log(dataset$SalePrice)) 
  
  dataset %>% select(-WoodDeckSF, -OpenPorchSF, -EnclosedPorch, -X3SsnPorch, -ScreenPorch, -X1stFlrSF, -X2ndFlrSF, -YearBuilt, -YrSold, -YearRemodAdd, -BsmtFullBath, -BsmtHalfBath, -BsmtFullBath, -FullBath, -HalfBath)
}

convertFactorsToBinaryColumns <- function(dataset, factor_columns = colnames(dataset)) {
  for (col in factor_columns) {
    column <- dataset[[col]]
    if (class(column) == "factor") {
      for (level in levels(column)) {
        if (!is.na(level)) {
          binaryColumn <- paste(col, str_remove_all(level, " "), sep = "_")
          dataset[[binaryColumn]] <- as.numeric(column == level)
        }
      }
      dataset <- dataset %>% select(-col)
    }
  }
  
  dataset
}

addNaFactor <- function(vector) {
  vector <- as.character(vector)
  vector[which(is.na(vector))] <- "NA"
  
  as.factor(vector)
}

yearToFactor <- function(yearVec) {
  as.factor(sapply(yearVec, function(year) {
    if (is.na(year)) {
      result <- "NA"
    } else if (year > 2000) {
      result <- "After 2000"
    } else if (year > 1980) {
      result <- "1981-2000"
    } else if (year > 1960) {
      result <- "1961-1980"
    } else if (year > 1940) {
      result <- "1941-1960"
    } else {
      result <- "Before 1940"
    }
    
    result
  }))
}

yesNoToBinary <- function(fact) {
  ifelse(fact == "Y", 1, 0)
}

condQualityToInt <- function(fact) {
  charVec <- as.character(fact)
  
  sapply(charVec, function(qual) {
    if (is.na(qual)) {
      result <- 0
    } else if (qual == "Ex") {
      result <- 5
    } else if (qual == "Gd") {
      result <- 4
    } else if (qual == "TA") {
      result <- 3
    } else if (qual == "Fa") {
      result <- 2
    } else if (qual == "Po") {
      result <- 1
    } else {
      result <- 0
    }
    
    result
  })
}

doubleInfoColumnsToDummies <- function(dataset, double_columns, new_column_prefix) {
  column_1 <- dataset[[double_columns[1]]]
  column_2 <- dataset[[double_columns[2]]]
  
  all_levels <- unique(c(levels(column_1), levels(column_2)))
  for (level in all_levels) {
    if (!is.na(level)) {
      binaryColumn <- paste(new_column_prefix, str_remove_all(level, " "), sep = "_")
      dataset[[binaryColumn]] <- as.numeric(column_1 == level | column_2 == level)
    }
  }
  
  dataset
}

RMSE <- function(true_ratings, predicted_ratings){
  sqrt(mean((true_ratings - predicted_ratings)^2))
}

train_set <- read.csv("data/train.csv", stringsAsFactors = T)
goal_set <- read.csv("data/test.csv", stringsAsFactors = T)

whole_set <- bind_rows(train_set, goal_set)

engineered_whole_set <- wrangleData(whole_set)

engineered_train_set <- engineered_whole_set %>% filter(SalePrice_Log > 0)

new_numeric_vars <- c("TotalSquare","Bathrooms","Age","SinceRenov","GarageAge","Freshness","Newness", "Overall","ExternalOverall","GarageOverall","LotArea_log","Spaciousness","GarageWow","OverallWow","BasementWow")

new_level_vars <- c("New", "Fresh")

for (var in new_level_vars) {
  print(engineered_train_set %>%
          ggplot(aes(x = .data[[var]], y = SalePrice_Log, group= .data[[var]])) + geom_boxplot())
}

for (var in new_numeric_vars) {
  print(engineered_train_set %>%
          ggplot(aes(x = .data[[var]], y = SalePrice_Log)) + geom_point())
}

engineered_train_set <- engineered_whole_set %>% filter(SalePrice_Log > 0)

mi_scores <- data.frame(col_name = colnames(engineered_train_set), mi = sapply(colnames(engineered_train_set), function(col_name) {
  mutinformation(X = as.integer(engineered_train_set[[col_name]]), Y = engineered_train_set$SalePrice)
}))

mi_scores %>% filter(!(col_name %in% c("SalePrice_Log", "Id"))) %>% arrange(desc(mi)) %>% tail(30)

engineered_whole_set <- engineered_whole_set %>% select(-SalePrice, -BldgType, -Fence, -RoofStyle, -BsmtCond, -LandContour, -PoolQC, -PoolArea, -RoofMatl, -LandSlope)

engineered_whole_set <- doubleInfoColumnsToDummies(engineered_whole_set, c("Condition1", "Condition2"), "Condition")
engineered_whole_set <- doubleInfoColumnsToDummies(engineered_whole_set, c("Exterior1st", "Exterior2nd"), "Ext")

bsmt_type_1 <- engineered_whole_set[["BsmtFinType1"]]
bsmt_type_2 <- engineered_whole_set[["BsmtFinType2"]]

all_levels <- unique(c(levels(bsmt_type_1), levels(bsmt_type_2)))

for (level in all_levels) {
  if (!is.na(level)) {
    bsmt1Vector <- as.numeric(bsmt_type_1 == level) * engineered_whole_set$BsmtFinSF1
    bsmt2Vector <- as.numeric(bsmt_type_2 == level) * engineered_whole_set$BsmtFinSF2
    
    summaryColumn <- paste("BF", str_remove_all(level, " "), sep = "_")
    engineered_whole_set[[summaryColumn]] <- bsmt1Vector + bsmt2Vector
  }
}

rm(bsmt1Vector, bsmt2Vector, bsmt_type_1, bsmt_type_2, columnName, new_level_vars, new_numeric_vars, row, var, summaryColumn, all_levels, level)

engineered_whole_set <- engineered_whole_set %>% select(-"Condition1", -"Condition2", -"Exterior1st", -"Exterior2nd", -"BsmtFinSF1", -"BsmtFinSF2", -"BsmtFinType1", -"BsmtFinType2")

set_for_clustering <- engineered_whole_set %>% select(OverallWow, LotArea, TotalSquare, GrLivArea, Spaciousness, Age, SinceRenov, PorchArea, Newness, Freshness)
k_m <- kmeans(set_for_clustering, centers = 10, iter.max = 30)

for (row in 1:nrow(k_m[["centers"]])) {
  columnName <- paste("Centroid", row, sep = "_")
  engineered_whole_set[[columnName]] <- sqrt(rowSums(sweep(as.matrix(set_for_clustering), 2, k_m[["centers"]][row,])**2))
}

engineered_whole_set <- convertFactorsToBinaryColumns(engineered_whole_set)

Ids <- engineered_whole_set$Id
SalePrices <- engineered_whole_set$SalePrice_Log

engineered_whole_set <- engineered_whole_set %>%
  select(-Id, -SalePrice_Log)
engineered_whole_set <- as.data.frame(scale(engineered_whole_set))

engineered_whole_set$Id <- Ids
engineered_whole_set$SalePrice_Log <- SalePrices

rm(Ids, SalePrices)

engineered_train_set <- engineered_whole_set %>% filter(SalePrice_Log > 0)

set.seed(1, sample.kind = "Rounding") 

glm_boost_every_model <- train(
  SalePrice_Log ~ .,
  method="glmboost",
  data = engineered_train_set,
  trControl = trainControl(method = "cv", number = 10),
)

glm_boost_every_model

set.seed(1, sample.kind = "Rounding") 

gauss_process_poly_model <- train(
  SalePrice_Log ~ .,
  method = "gaussprPoly",
  data = engineered_train_set,
  trControl = trainControl(method = "cv", number = 10)
)

gauss_process_poly_model

set.seed(1, sample.kind = "Rounding") 

forest_model <- train(
  SalePrice_Log ~ .,
  method = "rf",
  data = engineered_train_set,
  ntree = 200,
  trControl = trainControl(method = "cv", number = 10),
)

forest_model

set.seed(1, sample.kind = "Rounding") 

tree_model <- train(
  SalePrice_Log ~ .,
  method = "xgbTree",
  data = engineered_train_set,
  trControl = trainControl(method = "cv", number = 10)
)

tree_model

set.seed(1, sample.kind = "Rounding") 

bayes_neural_model <- train(
  SalePrice_Log ~ Centroid_9+Centroid_3+Centroid_5+Centroid_7+Fresh+New+OverallWow+OverallQual+TotalSquare+GrLivArea+Centroid_8+ExterQual+Centroid_10+TotalBsmtSF+KitchenQual+GarageArea+GarageWow+PorchArea+Freshness+ExternalOverall+Spaciousness+Age+SinceRenov+LotFrontage+Centroid_6+Centroid_1+Centroid_2,
  method = "brnn",
  data = engineered_train_set,
  trControl = trainControl(method = "cv", number = 10)
)

bayes_neural_model

set.seed(1, sample.kind = "Rounding") 

enet_model <- train(
  SalePrice_Log ~ .,
  method = "enet",
  data = engineered_train_set,
  trControl = trainControl(method = "cv", number = 10)
)

enet_model

glm_boost_every_result_test <- predict(glm_boost_every_model, engineered_train_set, type = "raw")
gauss_process_poly_result_test <- predict(gauss_process_poly_model, engineered_train_set, type = "raw")
rf_result_test <- predict(forest_model, engineered_train_set, type = "raw")
boost_tree_result_test <- predict(tree_model, engineered_train_set, type = "raw")
bayes_neural_result_test <- predict(bayes_neural_model, engineered_train_set, type = "raw")
enet_result_test <- predict(enet_model, engineered_train_set, type = "raw")

voting_result_test <- (glm_boost_every_result_test + gauss_process_poly_result_test  + rf_result_test  + boost_tree_result_test + bayes_neural_result_test + enet_result_test)/6
test_rmse <- c(
  RMSE(engineered_train_set$SalePrice_Log,glm_boost_every_result_test),
  RMSE(engineered_train_set$SalePrice_Log,gauss_process_poly_result_test),
  RMSE(engineered_train_set$SalePrice_Log,rf_result_test),
  RMSE(engineered_train_set$SalePrice_Log,boost_tree_result_test),
  RMSE(engineered_train_set$SalePrice_Log,bayes_neural_result_test),
  RMSE(engineered_train_set$SalePrice_Log,enet_result_test),
  RMSE(engineered_train_set$SalePrice_Log,voting_result_test)
  )

data.frame(model = c("glm_boost", "gauss_poly","rf", "boost_tree","bayes_nn", "elasticnet" , "voting"), test_rmse = test_rmse) %>%
  ggplot(aes(x = model, y = test_rmse, label = model)) +
  geom_point() +
    geom_text(hjust=0, vjust=0)

engineered_goal_set <- engineered_whole_set %>% filter(SalePrice_Log == 0)

glm_boost_every_result <- predict(glm_boost_every_model, engineered_goal_set, type = "raw")
gauss_process_poly_result <- predict(gauss_process_poly_model, engineered_goal_set, type = "raw")
rf_result <- predict(forest_model, engineered_goal_set, type = "raw")
boost_tree_result <- predict(tree_model, engineered_goal_set, type = "raw")
bayes_neural_result <- predict(bayes_neural_model, engineered_goal_set, type = "raw")
enet_result <- predict(enet_model, engineered_goal_set, type = "raw")
voting_result <- (glm_boost_every_result + gauss_process_poly_result  + rf_result  + boost_tree_result + bayes_neural_result + enet_result)/6

write.csv(data.frame(id=engineered_goal_set$Id, SalePrice=exp(glm_boost_every_result)), "estimations/glm_boost.csv", row.names = F)
write.csv(data.frame(id=engineered_goal_set$Id, SalePrice=exp(gauss_process_poly_result)), "estimations/gauss_poly.csv", row.names = F)
write.csv(data.frame(id=engineered_goal_set$Id, SalePrice=exp(rf_result)), "estimations/rf.csv", row.names = F)
write.csv(data.frame(id=engineered_goal_set$Id, SalePrice=exp(boost_tree_result)), "estimations/boost_tree.csv", row.names = F)
write.csv(data.frame(id=engineered_goal_set$Id, SalePrice=exp(bayes_neural_result)), "estimations/bayess_nn.csv", row.names = F)
write.csv(data.frame(id=engineered_goal_set$Id, SalePrice=exp(enet_result)), "estimations/enet.csv", row.names = F)
write.csv(data.frame(id=engineered_goal_set$Id, SalePrice=exp(voting_result)), "estimations/voting.csv", row.names = F)


validation_rmse <- c(0.13603, 0.13501, 0.12876, 0.12872, 0.13877, 0.13350, 0.12212) 

data.frame(model = c("glm_boost", "gauss_poly","rf", "boost_tree","bayes_nn", "elasticnet" , "voting"), validation_rmse = validation_rmse) %>%
  ggplot(aes(x = model, y = validation_rmse, label = model)) +
  geom_point() +
  geom_text(hjust=0, vjust=0)



