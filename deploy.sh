cd supersonic_doc
hugo --theme=hugo-book --baseURL="https://supersonicbi.github.io/" --buildDrafts
mv .\public\* ../
cd ../