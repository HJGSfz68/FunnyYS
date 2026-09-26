import { NextResponse } from 'next/server';

/**
 * API Route 共享守卫。
 * 本部署已移除访问密码：不再校验登录态，所有接口直接放行。
 */
export function guardRequest(_req: Request): NextResponse | null {
  void _req;
  return null;
}

export function jsonError(message: string, status: number): NextResponse {
  return NextResponse.json({ error: message }, { status });
}
