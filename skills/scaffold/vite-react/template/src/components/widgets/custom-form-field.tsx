import { cloneElement, type ReactElement } from 'react';
import { Controller, useFormContext } from 'react-hook-form';

import { Field, FieldDescription, FieldError, FieldLabel } from '@/components/ui/field';

interface CustomFormFieldProps {
  name: string;
  label: string;
  description?: string;
  children: ReactElement<Record<string, unknown>>;
}

export function CustomFormField({ name, label, description, children }: CustomFormFieldProps) {
  const { control } = useFormContext();

  return (
    <Controller
      name={name}
      control={control}
      render={({ field: { ref, ...field }, fieldState }) => {
        const descriptionId = description ? `${name}-description` : undefined;
        const errorId = fieldState.invalid ? `${name}-error` : undefined;
        const describedBy = [descriptionId, errorId].filter(Boolean).join(' ') || undefined;

        return (
          <Field data-invalid={fieldState.invalid}>
            <FieldLabel htmlFor={name}>{label}</FieldLabel>
            {cloneElement(children, {
              id: name,
              ref,
              'aria-invalid': fieldState.invalid,
              'aria-describedby': describedBy,
              ...field,
            })}
            {description && <FieldDescription id={descriptionId}>{description}</FieldDescription>}
            {fieldState.invalid && <FieldError id={errorId} errors={[fieldState.error]} />}
          </Field>
        );
      }}
    />
  );
}
