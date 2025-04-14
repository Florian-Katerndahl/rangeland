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

    print(is.integer(sum_rasters))

    # Calculate the number of values non-NA values for each cell
    count_rasters <- Reduce("+", lapply(rasters, function(x) {
        return(!is.na(x))
    }))

    print(is.integer(count_rasters))

    # Calculate the mean raster
    mean_raster <- sum_rasters %/% count_rasters

    return(mean_raster)
}

updateRasters <- function(inputFiles) {
    # load raster files into single SpatRaster
    rasters <- rast(inputFiles)

    # Merge rasters by maintaining the last non-NA value
    merged_raster <- app(rasters, function(x) {
        non_na_values <- na.omit(x)
        if (length(non_na_values) == 0) {
            return(1)
        }
        return(tail(non_na_values, 1)[1])
    })
}

updateOverviews <- function(inputFiles) {
	rasters <- rast(inputFiles)

	updatedRasters <- tapp(rasters, index = c(1, 2, 3), function(x) {
		non_na_values <- na.omit(x)
		if (length(non_na_values) == 0) {
			return(1)
		}
		return(tail(non_na_values, 1))
	})
}

readGDALOpts <- function(file) {
    if (!file.exists(file))
        stop("File not found")

    opts <- readLines(file)

    if (length(opts) == 0)
        return(NULL)

    opts <- opts[!grepl("EXTENSION|DRIVER", opts)]

    return(opts);
}

outputRaster <- function(raster, outputFile, fileType, NAflag, dataType, xBlocks, yBlocks, gdal_ops) {
    if (fileType == "tif") {
        writeRaster(
            raster,
            outputFile,
            datatype = dataType,
            NAflag = -9999,
            gdal = gdal_ops
        )
	} else if (fileType == "jpg") {
		writeRaster(
			raster,
			outputFile,
			datatype = dataType,
			filetype = "JP2OpenJPEG",
			gdal = c("INTERLEAVE=PIXEL", "YCBCR420=NO", "NBITS=11")
		)
	} else {
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

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
    stop("\nError: this program needs at least 4 inputs\n1: output filename\n2: mode (merge or update)\n3: custom file definition\n4-*: input file(s)", call.=FALSE)
}

fout <- args[1]
mode <- args[2]
cube_file <- args[3]
finp <- args[4:length(args)]

if (length(args) == 4) {
    file.copy(finp, fout)
} else {
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
	        outRaster <- updateRasters(finp)
    } else {
        stop("Unsupported mode supplied", call. = FALSE)
    }

    predefined_gdal_opts <- readGDALOpts(cube_file)

    outputRaster(outRaster, fout, fType, noData, dType, xBlockSize, yBlockSize, predefined_gdal_opts)
}
