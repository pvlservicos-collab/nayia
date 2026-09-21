import React from 'react'

interface FilterGridProps {
    children: React.ReactNode
}

export default function FilterGrid({ children }: FilterGridProps) {
    return (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 relative p-8">
            {/* 
         We need vertical dividers between columns.
         The easiest way with grid is to have the columns render their own border-right, 
         except the last one. 
         Or we can use a divide-x utility on the parent if it was flex, but grid is trickier.
         We can use "divide-x" logic by targeting children.
      */}
            {React.Children.map(children, (child, index) => {
                // Add specific classes to children to handle borders
                const isLast = React.Children.count(children) === index + 1

                return (
                    <div className={`
            relative px-6 first:pl-0 
            ${!isLast ? 'lg:border-r lg:border-gray-100' : ''}
            /* Add bottom border for mobile stacking if needed, but assuming desktop primary */
          `}>
                        {child}
                    </div>
                )
            })}
        </div>
    )
}
