# 前端标准镜像（Vue3 构建 → nginx 托管）
# 项目如需自定义，复制本文件到项目 frontend/Dockerfile 修改。
FROM node:20-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM nginx:alpine

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
