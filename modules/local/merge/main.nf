process MERGE {
    tag { id }
    label 'process_low'
    //label 'error_retry'

    container "docker.io/davidfrantz/force:3.8.01"

    input:
    tuple val(id), val(mode), path('input/?/*')
    path cube
    path creation_options

    output:
    tuple val(id), path("*.{tif,jpg}"), emit: tiles_merged
    path "versions.yml"               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    # get files to merge
    toMerge=\$(find input/ -type l -printf "%p ")
    numToMerge=\$(echo \$toMerge | wc -w) # WARN: this assumes no whitespaces in input file names!
    outFile=\$(find input -type l -printf "%f " | cut -d " " -f 1 | tr -d " ")

    if [[ \$numToMerge -gt 1 ]];
    then
        oneFile=\$(echo \$toMerge | cut -d " " -f 1)
        merge.r "\$outFile" "$mode" $creation_options \$toMerge
        echo "Merging Done"

        # apply meta
        force-mdcp \$oneFile \$outFile
    else

        ln -s \$toMerge \$outFile
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        force: \$(force -v | sed 's/.*: //')
        r-base: \$(echo \$(R --version 2>&1) | sed 's/^.*R version //; s/ .*\$//')
        raster: \$(Rscript -e "library(raster); cat(as.character(packageVersion('raster')))")
    END_VERSIONS
    """

}
