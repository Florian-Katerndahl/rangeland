#!/usr/bin/env Rscript

## Originally written by Felix Kummer and released under the MIT license.
## See git repository (https://github.com/nf-core/rangeland) for full license text.
## Modified by Florian Katerndahl<florian@katerndahl.com> (2025)

# Script for merging/updating FORCE Level 2 outputs

require(terra)

# assumes all layer have identical block sizes
getXBlockSize <- function(inputFile) {
    r <- rast(inputFile)
    blocks <- fileBlocksize(r)
    return(blocks[1, 2, drop = TRUE])
}

# assumes all layer have identical block sizes
getYBlockSize <- function(inputFile) {
    r <- rast(inputFile)
    blocks <- fileBlocksize(r)
    return(blocks[1, 1, drop = TRUE])
}

# assumes all layer have identical block sizes
getNoData <- function(inputFile) {
    r <- rast(inputFile)
    return(NAflag(r)[1])
}

getDataType <- function(inputFile) {
    r <- rast(inputFile)
    return(datatype(r, bylyr = FALSE))
}

mergeRasters <- function(inputFiles) {
    # Load input rasters
    rasters <- lapply(inputFiles, rast)

    # Calculate the sum of non-NA values across all rasters
    sum_rasters <- Reduce("+", lapply(rasters, function(x) {
        x[is.na(x)] <- 0
        return(x)
    }))

    # Calculate the number of values non-NA values for each cell
    count_rasters <- Reduce("+", lapply(rasters, function(x) {
        return(!is.na(x))
    }))

    # Calculate the mean raster
    mean_raster <- sum_rasters %/% count_rasters

    return(mean_raster)
}

updateRasters <- function(inputFiles) {
    # load raster files into single SpatRaster
    rasters <- rast(inputFiles)

    # Merge rasters by maintaining the last non-NA value
    updatedRasters <- app(rasters, function(x) {
        non_na_values <- na.omit(x)
        if (length(non_na_values) == 0) {
            return(1)
        }
        return(tail(non_na_values, 1)[1])
    }, cores=ifelse(Sys.getenv("QAIMERGECPUS") != "", as.integer(Sys.getenv("QAIMERGECPUS")), 1))

    return(updatedRasters)
}

mergeQaiFromValues <- function(pixels) {
  # width can be 1 or 2 bits, in decimal notation that's 1 or 3; to no needlessles construct the bitfields at runtime, they're stored
  # with correct initialization  
  qaiAttributes <- list(
    "_QAI_BIT_OFF_" = c("width" = 1, "position" =  0),
    "_QAI_BIT_CLD_" = c("width" = 3, "position" =  1),
    "_QAI_BIT_SHD_" = c("width" = 1, "position" =  3),
    "_QAI_BIT_SNW_" = c("width" = 1, "position" =  4),
    "_QAI_BIT_WTR_" = c("width" = 1, "position" =  5),
    "_QAI_BIT_AOD_" = c("width" = 3, "position" =  6),
    "_QAI_BIT_SUB_" = c("width" = 1, "position" =  8),
    "_QAI_BIT_SAT_" = c("width" = 1, "position" =  9),
    "_QAI_BIT_SUN_" = c("width" = 1, "position" = 10),
    "_QAI_BIT_ILL_" = c("width" = 3, "position" = 11),
    "_QAI_BIT_SLP_" = c("width" = 1, "position" = 13),
    "_QAI_BIT_WVP_" = c("width" = 1, "position" = 14)
  )
  
  if (!is.vector(pixels) && !is.integer(pixels)) {
    errorCondition("Supplied data is not an integer vector")
  }

  pixels <- pixels[!is.na(pixels)]

  if (length(pixels) == 0) {
    return(NA)
  }
  
  # extract merged qai flags, gives back the resulting bitfield for all QAI flags
  mergedQaiFlags <- purrr::imap_int(qaiAttributes, function(x, flag, pixel=pixels) {
    extracted_values <- bitwAnd(bitwShiftR(pixel, x["position"]), x["width"])
    retVal <- 0
    if (grepl("OFF", flag)) {
      retVal <- purrr::reduce(extracted_values, bitwAnd)
    } else if (grepl("SHD|SNW|WTR|SUB|SAT|SUN|SLP|WVP", flag)) {
      retVal <- purrr::reduce(extracted_values, bitwOr)
    } else if (grepl("CLD|AOD", flag)) {
      retVal <- max(extracted_values)
    } else if (grepl("ILL", flag)) {
      retVal <- min(extracted_values)
    } else {
      errorCondition("Unknown QAI flag")
    }
    return(bitwShiftL(retVal, x["position"]))
  })
  
  # merge flags back into one integer
  return(purrr::reduce(mergedQaiFlags, bitwOr))
}

#' Not only update rasters, but force consistent (i.e., order independent) values for quality
#' assurance information
#'
#' Sadly, it's rather slow
updateQualityAssurance <- function(inputFiles) {
  if (length(inputFiles) == 1) {
    return(terra::rast(inputFiles))
  }
  
  rasters <- terra::rast(inputFiles)

  updatedQAI <- terra::app(rasters, mergeQaiFromValues, cores=ifelse(Sys.getenv("QAIMERGECPUS") != "", as.integer(as.integer(Sys.getenv("QAIMERGECPUS")) / 2), 1))
  
  return(updatedQAI)
}

updateOverviews <- function(inputFiles) {
	rasters <- rast(inputFiles)

    if (any(is.nan(NAflag(rasters))))
		NAflag(rasters) <- 0

	updatedRasters <- tapp(rasters, index = c(1, 2, 3), function(x) {
		non_na_values <- na.omit(x)
		if (length(non_na_values) == 0) {
			return(1)
		}
		return(tail(non_na_values, 1))
	}, cores=ifelse(Sys.getenv("QAIMERGECPUS") != "", as.integer(Sys.getenv("QAIMERGECPUS")), 1))

    return(updatedRasters)
}

readGDALOpts <- function(file) {
    if (!file.exists(file))
        stop("File not found")

    opts <- readLines(file)

    if (length(opts) == 0)
        return(NULL)

    filteredOpts <- opts[!grepl("EXTENSION|DRIVER", opts)]

    customDriver <- opts[grepl("EXTENSION|DRIVER", opts)] |> split(" = ") |> (\(x) unlist(x)[2])()

    compactedContent <- gsub(" ", "", filteredOpts)

    return(list("opts"=compactedContent, "driver"=customDriver))
}

outputRaster <- function(raster, outputFile, fileType, NAflag, dataType, xBlocks, yBlocks, gdal_ops) {
    if (fileType == "tif" && !is.null(gdal_ops)) {
        # FORCE's BOA products
        writeRaster(
            raster,
            outputFile,
            filetype = fileType,
            datatype = dataType,
            NAflag = -9999,
            gdal = gdal_ops
        )
	} else if (fileType == "jpg") {
        # FORCE's OVV
		writeRaster(
			raster,
			outputFile,
			datatype = dataType,
			filetype = "JP2OpenJPEG",
            NAflag = NA,
			gdal = c("INTERLEAVE=PIXEL", "YCBCR420=NO", "JPEG_QUALITY=75") # for commit message: the bit depth was main culprit
		)
	} else {
        # other FORCE output
        writeRaster(
            raster,
            outputFile,
            datatype = dataType,
            NAflag = NAflag,
            gdal = c("COMPRESS=LZW", "PREDICTOR=2",
                     "NUM_THREADS=ALL_CPUS", "BIGTIFF=YES",
                     sprintf("BLOCKXSIZE=%s", xBlocks),
                     sprintf("BLOCKYSIZE=%s", yBlocks)
            )
        )
	}
}

isOptionFileValid <- function(path) {
    splittedPath <- unlist(strsplit(basename(path), ".", fixed = TRUE))
    if (splittedPath[length(splittedPath)] != "txt")
        return(FALSE)

    fileContent <- readLines(path, warn = FALSE) |>
        strsplit(" = ")
    
    return(!is.null(fileContent) && length(fileContent) > 1 && fileContent[[1]][1] == "DRIVER")
}

isNextflowEmptyFile <- function(path) {
    return(basename(path) == "NO_FILE")
}

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
    stop("\nError: this program needs at least 4 inputs\n1: output filename\n2: mode (merge or update)\n3: custom file definition (optional)\n4-*: input file(s)", call.=FALSE)
}

fout <- args[1]
mode <- args[2]
cube_file <- args[3]
finp <- args[4:length(args)]


if (length(args) == 4) {
    file.copy(finp, fout)
} else {
    if (isOptionFileValid(cube_file)) {
        predefined_gdal_opts <- readGDALOpts(cube_file)
    } else if (!isNextflowEmptyFile(cube_file)) {
        finp <- c(cube_file, finp) # mistakenly tried to parse data file as option file
    }

    # assumes all equal for all inputs
    xBlockSize <- getXBlockSize(finp[1])
    yBlockSize <- getYBlockSize(finp[1])
    noData <- getNoData(finp[1])
    dType <- getDataType(finp[1])
    fType <- tail(unlist(strsplit(basename(finp[1]), ".", fixed = TRUE)), n = 1)

    if (mode == "merge") {
        outRaster <- mergeRasters(finp)
    } else if (mode == "update") {
		if (fType == "jpg")
			outRaster <- updateOverviews(finp)
		else
	        outRaster <- updateQualityAssurance(finp)
    } else {
        stop("Unsupported mode supplied", call. = FALSE)
    }

    if (isOptionFileValid(cube_file) && grepl("_BOA", fout)) {
        # use predefined options only for BOA
        outputRaster(outRaster, fout, predefined_gdal_opts$driver, noData, dType, xBlockSize, yBlockSize, predefined_gdal_opts$opts)
    } else {
        # definitively don't use predefined options, esp. for overviews (thus, BOA can't be saved as JPG)
        outputRaster(outRaster, fout, fType, noData, dType, xBlockSize, yBlockSize, NULL)
    }


}
