# bring data into format that Felix expects
# while read line; do mkdir -p "level1/${line%/*}"; done < /lustre/geographie/fonda/dc/WRS2_EUROPE_DC.txt

# find /lustre/geographie/fonda/dc/level1 -type f -name 'L*.tar' -exec bash -c "BN=\$(basename {} | cut -d '_' -f 3); ln -s {} /lustre/fonda/b5/data-cube/level1/\$BN/\$(basename {})" bash {} \;

NXF_APPTAINER_CACHEDIR=/lustre/geographie/katerndf/apptainer-cache \
    nextflow run main.nf \
    -profile apptainer \
    -params-file params.yaml \
    -c custom.config \
    -cache true \
    -resume

# find $(grep -Po "(?=/lustre).*?(?=\")" params.yaml)"/preprocess" \
#     -type d -name 'X*' \
#     -exec cp -r "{}" /lustre/fonda/b5/data-cube/level2