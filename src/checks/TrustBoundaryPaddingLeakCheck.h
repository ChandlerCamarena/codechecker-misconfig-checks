#ifndef TRUST_BOUNDARY_PADDING_LEAK_CHECK_H
#define TRUST_BOUNDARY_PADDING_LEAK_CHECK_H

#include "clang-tidy/ClangTidyCheck.h"
#include "clang/AST/ASTContext.h"
#include "clang/ASTMatchers/ASTMatchFinder.h"

namespace clang::tidy {

/**
 * Detects record objects transferred by value across explicitly annotated
 * trust boundaries when the record type contains ABI-introduced padding
 * bytes that may not be fully initialized (thesis Chapter 6–7).
 *
 * Evidence levels (Chapter 5):
 *   E3 (high confidence)  — padding present + field-wise-only init visible
 *   E2 (bounded)          — padding present + initialization not determinable
 */

class TrustBoundaryPaddingLeakCheck : public ClangTidyCheck {
public:
  TrustBoundaryPaddingLeakCheck(StringRef Name, ClangTidyContext *Context)
      : ClangTidyCheck(Name, Context) {}

  void registerMatchers(ast_matchers::MatchFinder *Finder) override;
  void check(const ast_matchers::MatchFinder::MatchResult &Result) override;

private:
  // Returns true if FunctionDecl carries annotate("trust_boundary").
  static bool isTrustBoundary(const FunctionDecl *FD);

  // Returns true if the record type RecordDecl has any padding bytes under the
  // current ABI (field gaps or tail padding).
  static bool computeHasPadding(const RecordDecl *RD, ASTContext &Ctx);

  // Returns the padding size in bytes (for diagnostic messages).
  static uint64_t paddingBytes(const RecordDecl *RD, ASTContext &Ctx);

  // Initialization classification for the argument/return expression.
  enum class InitClass {
    WholeObject,  // T v = {0} or T v = {} — padding is zeroed
    FieldWise,    // member assignments only — padding may be stale
    Unknown,      // no local evidence
  };

  static InitClass classifyInit(const Expr *E, ASTContext &Ctx);

  // Emit the diagnostic and write an event record to the log file (if set).
  void emitDiagnostic(SourceLocation Loc, const RecordDecl *RD,
                      StringRef BoundaryFnName, StringRef EventKind,
                      InitClass IC, uint64_t PadBytes, ASTContext &Ctx);

  // Append one CSV row to the event log file (PADDING_LEAK_LOG env var).
  static void logEvent(StringRef BoundaryFn, StringRef EventKind,
                       StringRef TypeName, bool HasPadding, uint64_t PadBytes,
                       InitClass IC, bool DiagEmitted);
};

} // namespace clang::tidy

#endif
