interface SiteFooterProps {
  creditText?: string;
}

export function SiteFooter({ creditText = 'Built with templateCentral' }: SiteFooterProps) {
  return (
    <footer className="bg-foreground w-full border-t">
      <div className="max-w-site mx-auto px-6 py-6">
        <p className="text-background text-sm">{creditText}</p>
      </div>
    </footer>
  );
}
