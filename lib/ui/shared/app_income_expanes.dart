import 'package:flutter/material.dart';
import 'package:montra/resources/resources.dart';
import 'package:montra/ui/shared/app_colors.dart';

enum FinanceWidgetType {
  income,
  expense,
}

class IncomeExpenseWrapper extends StatelessWidget {
  final FinanceWidgetType type;
  const IncomeExpenseWrapper({Key? key, required this.type}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 80, maxWidth: 164),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        color: type == FinanceWidgetType.expense
            ? AppColor.baseRed[100]
            : AppColor.green,
      ),
      child: _IncomeExpenseBody(
        type: type,
      ),
    );
  }
}

/// this is the body widget which contains asset pick and Text
class _IncomeExpenseBody extends StatelessWidget {
  final FinanceWidgetType type;
  const _IncomeExpenseBody({Key? key, required this.type}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FractionallySizedBox(
        widthFactor: 0.8,
        alignment: Alignment.center,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: _ExpenseIncomeImg(
                type: type,
              ),
            ),
            Spacer(
              flex: 1,
            ),
            Expanded(
              flex: 4,
              child: _IncomeExpenseText(
                type: type,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// this is expense income img wrapper which contain two images one is arrow
/// second is money
class _ExpenseIncomeImg extends StatelessWidget {
  final FinanceWidgetType type;
  const _ExpenseIncomeImg({Key? key, required this.type}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 48, maxWidth: 48),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        color: Colors.white,
      ),
      child: _ExpenseIncomeContentWrapper(
        children: [
          Image(
              image: AssetImage(type == FinanceWidgetType.income
                  ? AppImages.incomeArrow
                  : AppImages.expenseArrow)),
          Image(
              image: AssetImage(type == FinanceWidgetType.income
                  ? AppImages.incomeLogo
                  : AppImages.expenseIcon)),
        ],
      ),
    );
  }
}

class _ExpenseIncomeContentWrapper extends StatelessWidget {
  final List<Widget>children;

  const _ExpenseIncomeContentWrapper({Key? key,
    required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        heightFactor: 0.65,
        widthFactor: 0.8,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children
        ),
      ),
    );
  }
}


class _IncomeExpenseText extends StatelessWidget {
  final FinanceWidgetType type;
  const _IncomeExpenseText({Key? key, required this.type}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final _style = TextStyle(
        color: AppColor.baseLight[80],
        fontFamily: 'Inter',
        fontWeight: FontWeight.w400,
        fontSize: 14);
    return FractionallySizedBox(
      heightFactor: 0.6,
      alignment: Alignment.center,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(type == FinanceWidgetType.income?'Income':'Expenses',style: _style,),
          Text(type == FinanceWidgetType.income?'0.0':'0.1',style: _style.copyWith(fontWeight: FontWeight.bold,fontSize: 18),),

        ],
      ),
    );
  }
}
