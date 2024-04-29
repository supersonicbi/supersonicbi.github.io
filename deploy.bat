cd supersonic-ai 
hugo --theme=ace-documentation --baseURL="https://supersonic-ai.github.io/" --buildDrafts
xcopy /QEY .\public\* ../
cd ../