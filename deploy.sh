rm -rf categories
rm -rf docs
rm -rf fonts
rm -rf img
rm -rf katex
rm -rf posts
rm -rf svg
rm -rf tags
cd supersonic_doc
hugo --theme=hugo-book --baseURL="https://supersonicbi.github.io/" --buildDrafts
mv public/* ../
cd ../