import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import React from 'react';

type CardProps = React.ComponentProps<typeof Card>;

interface CustomCardProps extends Omit<CardProps, 'children'> {
  className?: string;
  children?: React.ReactNode;
  header?: React.ReactNode;
  description?: React.ReactNode;
  contentClassName?: string;
}

export function CustomCard({
  className,
  contentClassName,
  children,
  header,
  description,
  ...cardProps
}: CustomCardProps) {
  return (
    <Card {...cardProps} className={className}>
      {(header || description) && (
        <CardHeader>
          {header && (
            <CardTitle className="text-xl leading-tight font-bold">
              {header}
            </CardTitle>
          )}
          {description && <CardDescription>{description}</CardDescription>}
        </CardHeader>
      )}
      <CardContent className={contentClassName}>{children}</CardContent>
    </Card>
  );
}
