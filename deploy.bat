cd supersonic_doc
hugo --theme=hugo-book --baseURL="https://supersonicbi.github.io/" --buildDrafts
xcopy /QEY .\public\* ../
cd ../