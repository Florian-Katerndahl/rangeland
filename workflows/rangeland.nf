/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_rangeland_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { PREPROCESSING } from '../subworkflows/local/preprocessing'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { UNTAR as UNTAR_INPUT; UNTAR as UNTAR_DEM; UNTAR as UNTAR_WVDB; UNTAR as UNTAR_REF } from '../modules/nf-core/untar/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow RANGELAND {

    main:

    // checks whether provided input is within provided time range
    def inRegion = {
        Integer date  = it.simpleName.split("_")[3]    as Integer
        Integer start = params.start_date.replace('-','') as Integer
        Integer end   = params.end_date.replace('-','')   as Integer

        return date >= start && date <= end
    }

    ch_versions      = Channel.empty()
    ch_multiqc_files = Channel.empty()
    //
    // Stage and validate input files
    //
    data           = Channel.empty()
    dem            = Channel.empty()
    wvdb           = Channel.empty()
    cube_file      = file( params.data_cube )
    aoi_file       = file( params.aoi )
    // see https://github.com/nextflow-io/nextflow/issues/1694 and https://github.com/nf-core/sarek/blob/a7679b9b5c178351b1e96a3ffe7ee81ddf9aad06/main.nf#L226
    custom_output  = params.l2_file_ouput_options ? file( params.l2_file_ouput_options ) : file( "$params.outdir/NO_FILE" )
    
    // what would be the appropriate method to create a new empty file?
    if (custom_output.name == "NO_FILE" && !custom_output.exists()) {
        error "ERROR: Create empty file at ${custom_output} and restart workflow"
    }

    //
    // MODULE: untar
    //
    tar_versions = Channel.empty()

    // TODO: create different channels for data already in FORCE structure (dir) and tared input (file, filtered to tar/tar.gz)
    // Determine type of params.input and extract when neccessary
    Channel.fromPath(params.input, type: 'file') // drop support for the directory structure
        | filter { dir -> inRegion(dir) }
        // keep branch closure so accessors below don't need any changes
        | branch { it ->
            archives : it.name.endsWith('tar') || it.name.endsWith('tar.gz')
                return tuple([:], it)
            dirs: true
                return it
            }
        | set { ch_input_types }

    UNTAR_INPUT(ch_input_types.archives)
    ch_untared_inputs = UNTAR_INPUT.out.untar.map{ it[1] }
    tar_versions = tar_versions.mix(UNTAR_INPUT.out.versions)

    Channel.empty()
        | mix(ch_untared_inputs, ch_input_types.dirs)
        | map {dir ->
                log.debug "Found ${dir}"
                dir
            }
        | set { data }

    data.ifEmpty {
        error "[nf-core/rangeland] ERROR: No directories found in input path or .tar file!"
    }

    // Determine type of params.dem and extract when neccessary
    // FIXME: expects base path (directory), in there needs to be a vrt file!
    ch_dem = Channel.fromPath(params.dem, type: 'dir')
    // branching not necessary when only accepting directories!
    ch_dem.branch { it
        archives : it.name.endsWith('tar') || it.name.endsWith('tar.gz')
            return tuple([:], it)
        dirs: true
            return file(it)
    }
    .set{ ch_dem_types }

    UNTAR_DEM(ch_dem_types.archives)
    ch_untared_dem = UNTAR_DEM.out.untar.map{ it[1] }
    tar_versions = tar_versions.mix(UNTAR_DEM.out.versions)

    dem = dem.mix(ch_untared_dem, ch_dem_types.dirs).first()

    // Determine type of params.wvdb and extract when neccessary
    ch_wvdb = Channel.fromPath(params.wvdb, type: 'dir')
    // branching not necessary when only accepting directories!
    ch_wvdb.branch { it
        archives : it.name.endsWith('tar') || it.name.endsWith('tar.gz')
            return tuple([:], it)
        dirs: true
            return file(it)
    }
    .set{ ch_wvdb_types }

    UNTAR_WVDB(ch_wvdb_types.archives)
    ch_untared_wvdb = UNTAR_WVDB.out.untar.map{ it[1] }
    tar_versions = tar_versions.mix(UNTAR_WVDB.out.versions)

    wvdb = wvdb.mix(ch_untared_wvdb, ch_wvdb_types.dirs).first()

    ch_versions = ch_versions.mix(tar_versions.first())

    //
    // SUBWORKFLOW: Preprocess satellite imagery
    //
    PREPROCESSING (
        data,
        dem,
        wvdb,
        cube_file,
        aoi_file,
        params.group_size,
        params.resolution,
        params.l2_output_format,
        custom_output,
        params.l2_output_dst,
        params.l2_output_aod,
        params.l2_output_wvp,
        params.l2_output_vzn,
        params.l2_output_hot,
        params.l2_output_ovv
    )
    ch_versions = ch_versions.mix(PREPROCESSING.out.versions)

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'rangeland_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    level2_ard     = PREPROCESSING.out.tiles_and_masks
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
