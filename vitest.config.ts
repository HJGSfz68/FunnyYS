import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    // 直播功能已移除，其对应的禁用代码与测试不再执行
    exclude: ['src/app/_live/**', 'src/app/api/_live/**'],
    environment: 'node',
  },
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
});
