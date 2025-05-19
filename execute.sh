JAVA_TOOL_OPTIONS=-Xmx2048m NXF_APPTAINER_CACHEDIR=/lustre/geographie/katerndf/apptainer-cache \
    nextflow run main.nf \
    -profile apptainer \
    -params-file params.yaml \
    -c custom.config \
    -resume
