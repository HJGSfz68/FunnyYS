'use client';

import { useAuth } from '@/components/auth';

/** 全站统一页脚：品牌 + 版本号 */
export function SiteFooter() {
  const { version } = useAuth();
  return (
    <footer className="border-t border-line py-4">
      <p className="text-center text-xs text-faint">
        FunnyYS{version ? ` v${version}` : ''}
        {' · '}
        AGPL-3.0 License
      </p>
    </footer>
  );
}
