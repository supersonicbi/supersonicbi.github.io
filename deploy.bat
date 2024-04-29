cd supersonicbi
hugo --theme=ace-documentation --baseURL="https://supersonicbi.github.io/" --buildDrafts
xcopy /QEY .\public\* ../
cd ../