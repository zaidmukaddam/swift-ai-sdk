import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';
import { BrandMark } from '@/components/logo';
import { gitConfig } from './shared';

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: <BrandMark />,
    },
    links: [
      {
        text: 'Docs',
        url: '/docs',
      },
      {
        text: 'Providers',
        url: '/docs/providers',
      },
      {
        text: 'Guides',
        url: '/docs/guides',
      },
    ],
    githubUrl: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
  };
}
