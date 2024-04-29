开发手册:
1. 本地安装好Go和HuGo(网上搜下，几分钟就好)
   Go version: 1.22.2   Hugo version: v0.125.3  
2. 所有文档用MarkDown编写，需要增加文档直接增加到supersonicbi/content目录即可
3. 本地查看效果直接执行compile-local.sh，然后浏览器输入http://localhost:1313/
4. 本地查看效果满意后，执行deploy.sh脚本，提交Git
5. Git会自动部署，等部署完毕，浏览器输入https://supersonicbi.github.io 即可看到效果
