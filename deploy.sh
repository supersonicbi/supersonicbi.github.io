cd supersonicbi
hugo --theme=ace-documentation --baseURL="https://supersonicbi.github.io/" --buildDrafts
mv .\public\* ../
cd ../