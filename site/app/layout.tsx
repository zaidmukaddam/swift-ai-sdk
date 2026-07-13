import { RootProvider } from 'fumadocs-ui/provider/next';
import './global.css';
import { Google_Sans_Flex } from 'next/font/google';

const googleSansFlex = Google_Sans_Flex({
  subsets: ['latin'],
});

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <html
      lang="en"
      className={googleSansFlex.className}
      suppressHydrationWarning
    >
      <body className="flex flex-col min-h-screen">
        <RootProvider>{children}</RootProvider>
      </body>
    </html>
  );
}
