include { FORCE_GENERATE_TILE_ALLOW_LIST }         from '../../modules/local/force-generate_tile_allow_list/main'
include { FORCE_GENERATE_ANALYSIS_MASK }           from '../../modules/local/force-generate_analysis_mask/main'
include { PREPROCESS_CONFIG }                      from '../../modules/local/preprocess_force_config/main'
include { FORCE_PREPROCESS }                       from '../../modules/local/force-preprocess/main'
include { MERGE }                                  from '../../modules/local/merge/main'

workflow PREPROCESSING {

    take:
        data
        dem
        wvdb
        cube_file
        aoi_file
        group_size
        resolution
        l2_output_format
        l2_file_ouput_options
        l2_output_dst
        l2_output_aod
        l2_output_wvp
        l2_output_vzn
        l2_output_hot
        l2_output_ovv

    main:

        // Closure to extract the parent directory of a file
        def extractDirectory = { it.parent.toString().substring(it.parent.toString().lastIndexOf('/') + 1 ) }

        def extractProduct = {
            def matcher = it.simpleName =~ /BOA|QAI|DST|AOD|WVP|VZN|HOT|OVV/

            assert matcher.size() == 1

            return matcher[0]
        }
        // Closure to extract both level 2 product type and how it needs to be handled
        def extractHandling = {
            open_options = [
                "BOA": "merge",
                "DST": "merge",
                "VZN": "merge",
                "HOT": "merge",
                "AOD": "merge",
                "WVP": "merge",
                "QAI": "update",
                "OVV": "update"
            ]

            return open_options[extractProduct(it)]
        }

        ch_versions = Channel.empty()

        FORCE_GENERATE_TILE_ALLOW_LIST( aoi_file, cube_file )
        ch_versions = ch_versions.mix(FORCE_GENERATE_TILE_ALLOW_LIST.out.versions)

        FORCE_GENERATE_ANALYSIS_MASK( aoi_file, cube_file, resolution )
        ch_versions = ch_versions.mix(FORCE_GENERATE_ANALYSIS_MASK.out.versions)

        //Group masks by tile
        masks = FORCE_GENERATE_ANALYSIS_MASK.out.masks.flatten().map{ x -> [ extractDirectory(x), x ] }

        // Preprocessing configuration
        PREPROCESS_CONFIG( data, cube_file, FORCE_GENERATE_TILE_ALLOW_LIST.out.tile_allow, dem, wvdb, aoi_file, l2_output_format,
                           l2_file_ouput_options, l2_output_dst, l2_output_aod, l2_output_wvp, l2_output_vzn, l2_output_hot,
                           l2_output_ovv )
        ch_versions = ch_versions.mix(PREPROCESS_CONFIG.out.versions.first())

        // Main preprocessing
        FORCE_PREPROCESS( PREPROCESS_CONFIG.out.preprocess_config_and_data)
        ch_versions = ch_versions.mix(FORCE_PREPROCESS.out.versions.first())

        // Group by tile, date and sensor
        FORCE_PREPROCESS.out.tiles
            | flatten
            | map { [ "${extractDirectory(it)}_${it.simpleName}", extractProduct(it), extractHandling(it), it]} // key; product; how to handle; files
            | groupTuple
            | branch {
                singular: it[3].size() == 1
                multi: it[3].size() > 1
            }
            | set { tiles }

        // FIXME: Does this break caching?
        tiles.multi
            | map { [it[0], it[1][0], it[2][0], it[3] ] } // "how to handle" is equal across all
              //Sort to ensure the same groups if you use resume
            | toSortedList { a,b -> a[3][0].simpleName <=> b[3][0].simpleName }
            | flatMap { it }
            | groupTuple( by: [0, 1], remainder: true, size: group_size )
            | mix ( tiles.singular )
            | map { [ it[0].substring( 0, 11 ), it[2][0], it[3].flatten() ]}
            | set { tiles_to_merge }

        MERGE( tiles_to_merge, cube_file, l2_file_ouput_options )
        ch_versions = ch_versions.mix(MERGE.out.versions.first())

    emit:
        tiles_and_masks = MERGE.out.tiles_merged.join( masks )
        versions        = ch_versions
}
