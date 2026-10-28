import { LinkList, type LinkItem } from '@/components/widgets';

interface SiteFooterProps {
  creditText?: string;
  links?: LinkItem[];
}

export function SiteFooter({
  creditText = 'Built with templateCentral',
  links = [],
}: SiteFooterProps) {
  return (
    <footer className="w-full bg-foreground">
      <div className="flex flex-col gap-4 px-6 py-6 sm:flex-row sm:items-center sm:justify-between">
        <p className="text-sm text-background">{creditText}</p>
        {links.length > 0 && (
          <nav aria-label="Footer">
            <LinkList links={links} className="text-sm text-background" />
          </nav>
        )}
      </div>
    </footer>
  );
}
