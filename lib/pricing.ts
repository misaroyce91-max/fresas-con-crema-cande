export type PricedTopping = { id?: string; name: string; price: number }
export type PricedCartItem = { unitPrice: number; toppings: PricedTopping[]; quantity: number }

export const toppingsUnitTotal = (toppings: PricedTopping[]) =>
  toppings.reduce((total, topping) => total + Number(topping.price || 0), 0)

export const itemUnitTotal = (item: PricedCartItem) =>
  Number(item.unitPrice || 0) + toppingsUnitTotal(item.toppings)

export const itemLineTotal = (item: PricedCartItem) => itemUnitTotal(item) * item.quantity

export const cartSubtotal = (items: PricedCartItem[]) =>
  items.reduce((total, item) => total + itemLineTotal(item), 0)

export const orderTotal = (subtotal: number, shipping: number, discount: number) =>
  Math.max(0, Number(subtotal) + Number(shipping) - Number(discount))
