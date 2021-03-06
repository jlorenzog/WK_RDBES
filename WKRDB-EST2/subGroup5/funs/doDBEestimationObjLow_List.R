#
# Drafts for function signatures. Dont implement yet
#

#' Transforms a FM and BV table into a length-stratified BV table
#' 
#' @details 
#'  if BVtable is NULL, a BVtable with BVtype and BVvalue set to NA will be created
#' 
#' @param FMtable
#' @param BVtable
#' @param stratificationYes code for encoding stratification in BVstratification. Included as default argument for now.
#' @noRd
makeBVtableList <- function(FMtable, BVtable, stratificationYes="Y"){
  
  if (is.null(FMtable)){
    return(BVtable)
  }
  
  # For now the SAid in BVtable = NA. Take it from FM table 
  BVtable$SAid <- NULL
  FMtable$stratname <- as.character(FMtable$FMclass)
  BVtable <- merge(BVtable, FMtable[,c("FMid", "stratname", "SAid")], by="FMid", all.x=T)
  
  # CHECK that numbers sampled in BVtable match the FMid's unique count 
  checknumsampled <- merge(BVtable[, c("FMid", "BVnumSamp")], as.data.frame(table(BVtable$FMid)), by.x = "FMid", by.y = "Var1")
  stopifnot(all(checknumsampled$BVnumSamp == checknumsampled$Freq))
  
  
  BVtable$BVstratification <- stratificationYes
  
  #make sure any additional stratification is added to the FM-stratification
  BVtable$BVstratumname <- paste(paste("FM:", BVtable$stratname, sep=""), BVtable$BVstratumname, sep="-") 
  #check that totals match FM table
  getfirst <- function(x){stopifnot(length(unique(x))==1); return(x[1]);}
  totalsInFmclass <- aggregate(list(tot=BVtable$BVnumTotal), by=list(FMid=BVtable$FMid, SAid = BVtable$SAid), FUN=getfirst)
  comptotals <- merge(totalsInFmclass, FMtable)
  stopifnot(all(comptotals$tot == comptotals$FMnumAtUnit))

  #remove column not in BV definition
  BVtable$stratname <- NULL
  
  # SPLIT to list per SAid
  BVtableList <- split(BVtable, BVtable$SAid)
  
  # CHECK if list length matches unique length SAid in BVtable (needed?)
  stopifnot(length(BVtableList) == length(unique(BVtable$SAid)))

  return(BVtableList)
}

#' sampling unit totals
#' 
#' @details contains design parameters and sample totals for a sampling unit
#'  \describe{
#'   \item{StatisticTable}{data.frame with the statistic of interest for each sampling unit}
#'   \item{DesignTable}{data.frame with columns 'aboveId', 'id',  and the design parameters for each sampling unit}
#'   \item{jiProb}{matrix with joint inclusion probabilites}
#'  }
#' 
"sampUnitData"

#' Estimation objecy lower hierarhcy
#'
#'  @details list with the following members
#'  \describe{
#'   \item{Hierarchy}{character: Code identifying the type of lower hiearchy (A,B,C or D).}
#'   \item{Value}{character: Code identifying the total provided in the PSU design table}
#'   \item{sampleData}{list of data for each sample with members formatted as \code{\link{sampUnitData}}}
#'  }
#' 
#' @rname DBEestimObjLow
#' 
"DBEestimObjLow"

#' Prepares specimen parameters
#' 
#' @description 
#'  Prepares data for estimation of statistics calculated for specimen parameters.
#'  Should be applied to BV and FM table from all samples.
#'
#' @details 
#'  Estimation of number at length can be based on individual parameters (BV table) or sorting in length groups (FM table). 
#'  This is not supported by this function.
#'  (Perhaps FMtable could be prepared directly to the format 'DBEresultsTotalPointLow' returned by computeDBEresultsTotalPointLow)
#' 
#'  The parameter 'stat' specifies the statstic of interest and may be specified as:
#'  \descibe{
#'   \item{number}{the total number of specimens}
#'  }
#' 
#' @param FMtable for all samples
#' @param BVtable for all samples
#' @param lowerHierarchy character identifying the lower hierarchy to extract
#' @param stat character identifying the statistic of interest, for now this supports the somewhat contrived options 'number' and 'countAtAge6'
#' @return \code{\link{sampUnitData}} lower hiearchy data prepared for estimation
doDBEestimationObjLowSpecimenParamsMultSa <- function(FMtable=NULL, BVtable=NULL, lowerHierarchy=c("A","C"), stat=c("number", "numberAtAge6", "numberAtAge"), ages=1:20){

  if (lowerHierarchy == "A"){
    if (any(is.na(BVtable$FMid)) | !all(BVtable$FMid %in% FMtable$FMid)){
      stop("BVtable does not correspond to FMtable")
    }
    
    BVtableList <- makeBVtableList(FMtable, BVtable)
  }
  else if (lowerHierarchy == "B"){
    stop("No estimation from specimen parameters is possible for lower hierarchy B.")  }
  else if (lowerHierarchy == "C"){
    stopifnot(is.null(FMtable))
    # CHECK needed
    BVtableList <- split(BVtable, BVtable$SAid)
  }
  else if (lowerHierarchy == "D"){
    stop("No lower hierarchy estimation possible for lower hierarchy D.")
  }
  else{
    stop("Lower hierarchy " + lowerHierarchy + " is not implemented.")
  }
  
  if (stat=="number"){
    BVtableList <-lapply(1:length(BVtableList), function(x){
      BVtableList[[x]][!duplicated(BVtableList[[x]][["BVfishId"]]), ]
      cbind(BVtableList[[x]], count = 1)
    })
    var <- "count"
  }
  else if (stat=="numberAtAge6"){
    BVtableList <-lapply(1:length(BVtableList), function(x){
      BVtableList[[x]][BVtableList[[x]][["BVtype"]] == "Age", ]
      stopifnot(!any(duplicated(BVtableList[[x]][["BVfishId"]])))
      cbind(BVtableList[[x]], countAtAge6 = as.numeric(BVtableList[[x]][["BVvalue"]] == 6))
    })
    var <- "countAtAge6"
  }
  else if (stat=="numberAtAge"){
    BVtableList <-lapply(1:length(BVtableList), function(x){
      if(length(ages) > 0){ 
        yy <- paste0("Age_", sort(ages)) # this works also with a vector of ages not in sequence
        cbind(BVtableList[[x]], t(sapply(BVtableList[[x]][["BVvalue"]], function(i) 
          setNames(as.numeric(grepl(paste0('\\<', i ,'\\>'), gsub("Age_", "", yy))), yy))))
      }else{
        stop("Please provide an age vector")
      }
    })
    var <- yy
  }
  
  else{
    stop("Option ", stat, " is not supported for parameter 'stat'.")
  }
  
 # CREAT output list (nested output sublists )
  output <- list()
  change <-  function(x){
    output$StatisticTable <- BVtableList[[x]][,c("BVfishId", var)]
    names(output$StatisticTable) <- c("id", var)
    output$DesignTable <-BVtableList[[x]][,c("BVfishId", "BVstratification", "BVstratumname", "BVselectMeth", "BVnumTotal", "BVnumSamp", "BVselProp", "BVinclProp")]
    names(output$DesignTable) <- c("id", "stratification", "stratumname", "selectMeth", "numTotal", "numSamp", "selProb", "inclProb")
    output$jiProb <- matrix(nrow=nrow(output$DesignTable), ncol=nrow(output$DesignTable))
    colnames(output$jiProb) <- output$DesignTable$id
    rownames(output$jiProb) <- output$DesignTable$id
    return(output)
  }
  output <- lapply(1:length(BVtableList), change)
  
  return(output)
}
