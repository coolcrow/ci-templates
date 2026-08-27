# 后端标准镜像（FastAPI + uvicorn）
# 项目如需自定义（如额外系统依赖、不同入口），复制本文件到项目 backend/Dockerfile 修改即可，
# 流水线检测到项目内存在 Dockerfile 时优先使用项目内的。
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# 入口约定：backend/app/main.py 中存在 FastAPI 实例 app
# 如入口不同，在项目内覆盖本 CMD
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
