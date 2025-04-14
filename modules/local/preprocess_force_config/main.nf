process PREPROCESS_CONFIG {
    tag { data.simpleName }
    label 'process_single'
    label 'error_retry'

    container "docker.io/davidfrantz/force:3.8.01"

    input:
    path data
    path cube
    path tile
    path dem
    path wvdb
    path aoi
    val l2_output_format
    path optional_custom_options
    val l2_output_dst
    val l2_output_aod
    val l2_output_wvp
    val l2_output_vzn
    val l2_output_hot
    val l2_output_ovv

    output:
    tuple path("*.prm"), path(data), path(cube), path(tile), path(dem), path(wvdb), path(aoi), path(optional_custom_options), emit: preprocess_config_and_data
    path "versions.yml"                                                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def coo = optional_custom_options.name == 'NO_FILE' ? "NULL" : './' + optional_custom_options
    """
    BASE=\$(basename $data)

    # generate parameterfile from scratch
    force-parameter -c ./preprocess_${tile}.prm LEVEL2
    PARAM=\$BASE.prm
    mv *.prm \$PARAM

    # read grid definition
    CRS=\$(sed '1q;d' $cube)
    ORIGINX=\$(sed '2q;d' $cube)
    ORIGINY=\$(sed '3q;d' $cube)
    TILESIZE=\$(sed '6q;d' $cube)
    BLOCKSIZE=\$(sed '7q;d' $cube)

    # get dem vrt file
    dem_file=\$(find $dem/ -type f -name "*.vrt" -print | head -n 1)

    # set parameters
    sed -i "/^FILE_AOI /c\\FILE_AOI = $aoi" \$PARAM
    sed -i "/^FILE_DEM /c\\FILE_DEM = \$dem_file" \$PARAM
    sed -i "/^DIR_WVPLUT /c\\DIR_WVPLUT = $wvdb" \$PARAM
    sed -i "/^FILE_TILE /c\\FILE_TILE = $tile" \$PARAM
    sed -i "/^TILE_SIZE /c\\TILE_SIZE = \$TILESIZE" \$PARAM
    sed -i "/^BLOCK_SIZE /c\\BLOCK_SIZE = \$BLOCKSIZE" \$PARAM
    sed -i "/^ORIGIN_LON /c\\ORIGIN_LON = \$ORIGINX" \$PARAM
    sed -i "/^ORIGIN_LAT /c\\ORIGIN_LAT = \$ORIGINY" \$PARAM
    sed -i "/^PROJECTION /c\\PROJECTION = \$CRS" \$PARAM
    sed -i "/^ERASE_CLOUDS /c\\ERASE_CLOUDS = TRUE" \$PARAM
    sed -i "/^MAX_CLOUD_COVER_FRAME /c\\MAX_CLOUD_COVER_FRAME = 90" \$PARAM
    sed -i "/^MAX_CLOUD_COVER_TILE /c\\MAX_CLOUD_COVER_TILE = 90" \$PARAM

    # output options
    sed -i "/^OUTPUT_FORMAT /c\\OUTPUT_FORMAT = $l2_output_format" \$PARAM
    sed -i "/^FILE_OUTPUT_OPTIONS /c\\FILE_OUTPUT_OPTIONS = $coo" \$PARAM
    sed -i "/^OUTPUT_DST /c\\OUTPUT_DST = $l2_output_dst" \$PARAM
    sed -i "/^OUTPUT_AOD /c\\OUTPUT_AOD = $l2_output_aod" \$PARAM
    sed -i "/^OUTPUT_WVP /c\\OUTPUT_WVP = $l2_output_wvp" \$PARAM
    sed -i "/^OUTPUT_VZN /c\\OUTPUT_VZN = $l2_output_vzn" \$PARAM
    sed -i "/^OUTPUT_HOT /c\\OUTPUT_HOT = $l2_output_hot" \$PARAM
    sed -i "/^OUTPUT_OVV /c\\OUTPUT_OVV = $l2_output_ovv" \$PARAM

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        force: \$(force -v | sed 's/.*: //')
    END_VERSIONS
    """

}
